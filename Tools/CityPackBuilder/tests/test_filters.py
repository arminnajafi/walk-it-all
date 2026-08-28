import json

from shapely.geometry import Polygon

from city_pack_builder.build import (
    Segment,
    classify_way,
    connectivity_stats,
    deduplicate_segments,
    geometry_audit,
    file_sha256,
    geodesic_polyline_length,
    named_goal_miles_by_kind,
    stable_segment_id,
    topology_audit,
    way_intersects_boundary,
    write_review_geojson,
)


def test_includes_public_streets_and_paths() -> None:
    assert classify_way({"highway": "residential"}).kind == "street"
    assert classify_way({"highway": "footway"}).kind == "parkPath"
    assert classify_way({"highway": "steps"}).kind == "steps"


def test_excludes_private_and_service_only_geometry() -> None:
    assert not classify_way({"highway": "path", "access": "private"}).included
    assert not classify_way({"highway": "service", "service": "parking_aisle"}).included
    assert not classify_way({"highway": "footway", "footway": "sidewalk"}).included
    assert not classify_way({"highway": "footway", "access": "customers"}).included


def test_keeps_crossings_only_as_graph_connectors() -> None:
    crossing = classify_way({"highway": "footway", "footway": "crossing"})
    assert crossing.included
    assert crossing.kind == "connector"
    assert not crossing.counts_toward_coverage


def test_conditionally_includes_public_greenways() -> None:
    assert not classify_way({"highway": "cycleway"}).included
    assert classify_way({"highway": "cycleway", "foot": "yes"}).kind == "connector"


def test_stable_ids_and_length() -> None:
    coordinates = ((-73.99, 40.75), (-73.99, 40.751))
    first = stable_segment_id(10, 1, 2, coordinates)
    second = stable_segment_id(10, 1, 2, coordinates)
    assert first == second
    assert 110 < geodesic_polyline_length(coordinates) < 112


def test_source_checksum_is_streamed_and_stable(tmp_path) -> None:
    source = tmp_path / "source.bin"
    source.write_bytes(b"walk-it-all" * 1_000)
    assert file_sha256(source, chunk_size=7) == file_sha256(source, chunk_size=4_096)


def test_connectivity_uses_graph_only_connectors_without_counting_their_length() -> None:
    coordinates = ((-73.99, 40.75), (-73.99, 40.751))
    segments = [
        Segment("a", 1, 2, "street", 100, 1, None, coordinates, True),
        Segment("crossing", 2, 3, "connector", 10, 2, None, coordinates, False),
        Segment("b", 3, 4, "parkPath", 100, 3, None, coordinates, True),
    ]
    stats = connectivity_stats(segments)
    assert stats["component_count"] == 1
    assert stats["largest_component_goal_length_miles"] == 200 / 1_609.344


def test_boundary_prefilter_scopes_way_counts_to_manhattan_geometry() -> None:
    boundary = Polygon(((0, 0), (2, 0), (2, 2), (0, 2)))
    assert way_intersects_boundary(((-1, 1), (1, 1)), boundary)
    assert not way_intersects_boundary(((3, 3), (4, 4)), boundary)
    assert not way_intersects_boundary(((1, 1),), boundary)


def test_named_and_unnamed_goal_miles_are_reported_by_kind() -> None:
    coordinates = ((0.2, 0.2), (0.8, 0.8))
    segments = [
        Segment("named", 1, 2, "street", 1_609.344, 1, "Broadway", coordinates, True),
        Segment("unnamed", 2, 3, "street", 804.672, 2, None, coordinates, True),
        Segment("graph", 3, 4, "connector", 1_609.344, 3, None, coordinates, False),
    ]

    report = named_goal_miles_by_kind(segments)

    assert report["street"] == {
        "named_miles": 1.0,
        "unnamed_miles": 0.5,
        "total_miles": 1.5,
    }
    assert report["connector"]["total_miles"] == 0


def test_geometry_and_topology_audits_expose_reviewable_failures() -> None:
    boundary = Polygon(((0, 0), (2, 0), (2, 2), (0, 2)))
    first = Segment(
        "first", 1, 2, "street", 100, 1, "First", ((0.2, 0.2), (0.8, 0.8)), True
    )
    duplicate = Segment(
        "duplicate", 2, 3, "street", 100, 2, None, ((0.8, 0.8), (0.2, 0.2)), True,
        layer=1, bridge=True
    )
    outside = Segment(
        "outside", 4, 5, "parkPath", 100, 3, None, ((3.0, 3.0), (4.0, 4.0)), True,
        tunnel=True
    )

    geometry = geometry_audit([first, duplicate, outside], boundary)
    topology = topology_audit([first, duplicate, outside])

    assert not geometry["all_segments_within_boundary"]
    assert geometry["outside_boundary_count"] == 1
    assert geometry["duplicate_geometry_count"] == 1
    assert topology["shared_node_count"] == 1
    assert topology["mixed_layer_shared_node_count"] == 1
    assert topology["bridge_segment_count"] == 1
    assert topology["tunnel_segment_count"] == 1


def test_exact_same_level_geometry_is_deduplicated_deterministically() -> None:
    first = Segment(
        "z-id", 1, 2, "parkPath", 100, 20, None, ((0.2, 0.2), (0.8, 0.8)), True
    )
    reverse = Segment(
        "a-id", 2, 1, "parkPath", 100, 10, None, ((0.8, 0.8), (0.2, 0.2)), True
    )
    different_layer = Segment(
        "layered", 3, 4, "parkPath", 100, 30, None, ((0.2, 0.2), (0.8, 0.8)), True,
        layer=1,
    )

    result, report = deduplicate_segments([first, reverse, different_layer])

    assert {segment.identifier for segment in result} == {"a-id", "layered"}
    assert report == {
        "removed_segment_count": 1,
        "removed_geometry_groups": [{"kept_id": "a-id", "removed_ids": ["z-id"]}],
    }


def test_component_histogram_details_and_suspicious_geojson(tmp_path) -> None:
    segments = [
        Segment("large-a", 1, 2, "street", 100, 1, "A", ((0, 0), (1, 0)), True),
        Segment("large-b", 2, 3, "street", 100, 2, "B", ((1, 0), (2, 0)), True),
        Segment("small", 10, 11, "parkPath", 50, 3, None, ((0, 1), (1, 1)), True),
    ]

    stats = connectivity_stats(segments)
    output = tmp_path / "review.geojson"
    review = write_review_geojson(output, segments)
    document = json.loads(output.read_text())

    assert stats["component_count"] == 2
    assert stats["component_size_histogram"] == {"1": 1, "2-5": 1}
    assert stats["largest_components"][1]["bounding_box"]["min_latitude"] == 1
    assert review["suspicious_segment_count"] == 1
    assert document["features"][0]["properties"]["reasons"] == [
        "unnamed",
        "disconnected_component",
    ]
