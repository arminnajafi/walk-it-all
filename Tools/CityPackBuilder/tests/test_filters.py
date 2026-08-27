from city_pack_builder.build import (
    Segment,
    classify_way,
    connectivity_stats,
    geodesic_polyline_length,
    stable_segment_id,
)


def test_includes_public_streets_and_paths() -> None:
    assert classify_way({"highway": "residential"}).kind == "street"
    assert classify_way({"highway": "footway"}).kind == "parkPath"
    assert classify_way({"highway": "steps"}).kind == "steps"


def test_excludes_private_and_service_only_geometry() -> None:
    assert not classify_way({"highway": "path", "access": "private"}).included
    assert not classify_way({"highway": "service", "service": "parking_aisle"}).included
    assert not classify_way({"highway": "footway", "footway": "sidewalk"}).included


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
