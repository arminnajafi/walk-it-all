from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import UTC, datetime
import hashlib
import json
import math
from pathlib import Path
import sqlite3
from typing import Any, Callable, Iterable

import osmium
from shapely.geometry import LineString, MultiLineString, Polygon, mapping, shape


ALWAYS_INCLUDED_HIGHWAYS = {
    "primary",
    "secondary",
    "tertiary",
    "residential",
    "living_street",
    "unclassified",
    "pedestrian",
    "footway",
    "path",
    "steps",
}
CONDITIONAL_HIGHWAYS = {"cycleway", "track", "service"}
PUBLIC_FOOT_VALUES = {"yes", "designated", "permissive", "official"}
PROHIBITED_ACCESS = {"no", "private"}
RESTRICTED_ACCESS = {"customers", "delivery", "destination", "permit"}
MINIMUM_PATH_LENGTH_METERS = 12.0


@dataclass(frozen=True)
class Eligibility:
    included: bool
    kind: str | None
    reason: str
    counts_toward_coverage: bool = True


@dataclass(frozen=True)
class Segment:
    identifier: str
    start_node: int
    end_node: int
    kind: str
    length_meters: float
    source_way_id: int
    name: str | None
    coordinates: tuple[tuple[float, float], ...]
    counts_toward_coverage: bool
    layer: int = 0
    bridge: bool = False
    tunnel: bool = False


def classify_way(tags: dict[str, str]) -> Eligibility:
    highway = tags.get("highway")
    foot = tags.get("foot")
    access = tags.get("access")

    if not highway:
        return Eligibility(False, None, "missing_highway")
    if highway == "construction" or tags.get("construction"):
        return Eligibility(False, None, "construction")
    if access in PROHIBITED_ACCESS or foot in PROHIBITED_ACCESS:
        return Eligibility(False, None, "non_public_access")
    if access in RESTRICTED_ACCESS or foot in RESTRICTED_ACCESS:
        return Eligibility(False, None, "restricted_access")
    if tags.get("indoor") == "yes" or tags.get("area") == "yes":
        return Eligibility(False, None, "indoor_or_area")
    if tags.get("footway") == "sidewalk":
        return Eligibility(False, None, "sidewalk_proxy")
    if highway == "footway" and tags.get("footway") == "crossing":
        return Eligibility(True, "connector", "graph_only_crossing", False)

    if highway in CONDITIONAL_HIGHWAYS:
        if highway == "service" and tags.get("service") in {"parking_aisle", "driveway", "drive-through"}:
            return Eligibility(False, None, "service_only")
        if foot not in PUBLIC_FOOT_VALUES:
            return Eligibility(False, None, "conditional_without_public_foot")

    if highway not in ALWAYS_INCLUDED_HIGHWAYS and highway not in CONDITIONAL_HIGHWAYS:
        return Eligibility(False, None, "unsupported_highway")

    if highway == "steps":
        kind = "steps"
    elif highway == "pedestrian":
        kind = "pedestrian"
    elif highway in {"footway", "path"}:
        kind = "greenway" if tags.get("bicycle") in PUBLIC_FOOT_VALUES else "parkPath"
    elif highway in {"cycleway", "track", "service"}:
        kind = "connector"
    else:
        kind = "street"
    return Eligibility(True, kind, "included")


class IntersectionCounter(osmium.SimpleHandler):
    def __init__(self, boundary: Polygon) -> None:
        super().__init__()
        self.boundary = boundary
        self.boundary_bounds = boundary.bounds
        self.node_use: Counter[int] = Counter()
        self.exclusions: Counter[str] = Counter()

    def way(self, way: osmium.osm.Way) -> None:
        nodes = [node for node in way.nodes if node.location.valid()]
        coordinates = tuple((node.location.lon, node.location.lat) for node in nodes)
        if not way_intersects_boundary(coordinates, self.boundary, self.boundary_bounds):
            return
        tags = {tag.k: tag.v for tag in way.tags}
        eligibility = classify_way(tags)
        if not eligibility.included:
            self.exclusions[eligibility.reason] += 1
            return
        self.node_use.update(node.ref for node in nodes)


class SegmentCollector(osmium.SimpleHandler):
    def __init__(self, boundary: Polygon, intersection_nodes: set[int]) -> None:
        super().__init__()
        self.boundary = boundary
        self.intersection_nodes = intersection_nodes
        self.segments: list[Segment] = []
        self.exclusions: Counter[str] = Counter()

    def way(self, way: osmium.osm.Way) -> None:
        tags = {tag.k: tag.v for tag in way.tags}
        eligibility = classify_way(tags)
        if not eligibility.included or eligibility.kind is None:
            return

        nodes = [node for node in way.nodes if node.location.valid()]
        if len(nodes) < 2:
            self.exclusions["missing_geometry"] += 1
            return

        split_indices = {0, len(nodes) - 1}
        split_indices.update(
            index for index, node in enumerate(nodes) if node.ref in self.intersection_nodes
        )
        ordered_indices = sorted(split_indices)

        for start_index, end_index in zip(ordered_indices, ordered_indices[1:]):
            if end_index <= start_index:
                continue
            piece_nodes = nodes[start_index : end_index + 1]
            coordinates = [(node.location.lon, node.location.lat) for node in piece_nodes]
            clipped = LineString(coordinates).intersection(self.boundary)
            for line in line_parts(clipped):
                part_coordinates = tuple((float(x), float(y)) for x, y in line.coords)
                if len(part_coordinates) < 2:
                    continue
                length = geodesic_polyline_length(part_coordinates)
                if eligibility.kind in {"parkPath", "greenway", "connector"} and length < MINIMUM_PATH_LENGTH_METERS:
                    self.exclusions["insignificant_path"] += 1
                    continue

                start_node = endpoint_id(
                    piece_nodes[0].ref,
                    part_coordinates[0],
                    coordinates[0],
                )
                end_node = endpoint_id(
                    piece_nodes[-1].ref,
                    part_coordinates[-1],
                    coordinates[-1],
                )
                self.segments.append(Segment(
                    identifier=stable_segment_id(
                        way.id,
                        start_node,
                        end_node,
                        part_coordinates,
                    ),
                    start_node=start_node,
                    end_node=end_node,
                    kind=eligibility.kind,
                    length_meters=length,
                    source_way_id=way.id,
                    name=tags.get("name"),
                    coordinates=part_coordinates,
                    counts_toward_coverage=eligibility.counts_toward_coverage,
                    layer=parse_layer(tags.get("layer")),
                    bridge=tags.get("bridge") not in {None, "no"},
                    tunnel=tags.get("tunnel") not in {None, "no"},
                ))


def parse_layer(value: str | None) -> int:
    if value is None:
        return 0
    try:
        return int(float(value.split(";")[0]))
    except ValueError:
        return 0


def way_intersects_boundary(
    coordinates: tuple[tuple[float, float], ...],
    boundary: Polygon,
    boundary_bounds: tuple[float, float, float, float] | None = None,
) -> bool:
    if len(coordinates) < 2:
        return False
    min_longitude = min(value[0] for value in coordinates)
    max_longitude = max(value[0] for value in coordinates)
    min_latitude = min(value[1] for value in coordinates)
    max_latitude = max(value[1] for value in coordinates)
    boundary_min_lon, boundary_min_lat, boundary_max_lon, boundary_max_lat = (
        boundary_bounds or boundary.bounds
    )
    if (
        max_longitude < boundary_min_lon
        or min_longitude > boundary_max_lon
        or max_latitude < boundary_min_lat
        or min_latitude > boundary_max_lat
    ):
        return False
    return LineString(coordinates).intersects(boundary)


def line_parts(geometry: object) -> Iterable[LineString]:
    if isinstance(geometry, LineString):
        yield geometry
    elif isinstance(geometry, MultiLineString):
        yield from geometry.geoms


def load_largest_polygon(path: Path) -> Polygon:
    document = json.loads(path.read_text())
    geometry = document["features"][0]["geometry"] if document.get("type") == "FeatureCollection" else document
    value = shape(geometry)
    if value.geom_type == "Polygon":
        return value
    if value.geom_type == "MultiPolygon":
        return max(value.geoms, key=lambda polygon: polygon.area)
    raise ValueError(f"Expected Polygon or MultiPolygon, got {value.geom_type}")


def stable_segment_id(
    way_id: int,
    start_node: int,
    end_node: int,
    coordinates: tuple[tuple[float, float], ...],
) -> str:
    normalized = ";".join(f"{longitude:.7f},{latitude:.7f}" for longitude, latitude in coordinates)
    geometry_hash = hashlib.sha256(normalized.encode()).hexdigest()[:12]
    return f"osm-{way_id}-{start_node}-{end_node}-{geometry_hash}"


def file_sha256(path: Path, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(chunk_size):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_geometry(
    coordinates: tuple[tuple[float, float], ...],
) -> tuple[tuple[float, float], ...]:
    forward = tuple((round(longitude, 7), round(latitude, 7)) for longitude, latitude in coordinates)
    reverse = tuple(reversed(forward))
    return min(forward, reverse)


def deduplicate_segments(segments: list[Segment]) -> tuple[list[Segment], dict[str, Any]]:
    """Remove only exact, semantically equivalent copies of the same path.

    Layer and structure tags are part of the key so coincident geometry at a
    different grade is never merged. The lexicographically smallest stable ID
    wins, making the output independent of source traversal order.
    """
    groups: dict[tuple[Any, ...], list[Segment]] = defaultdict(list)
    for segment in segments:
        groups[(
            canonical_geometry(segment.coordinates),
            segment.kind,
            segment.counts_toward_coverage,
            segment.layer,
            segment.bridge,
            segment.tunnel,
        )].append(segment)

    kept_ids: set[str] = set()
    removed_groups: list[dict[str, Any]] = []
    for values in groups.values():
        ordered = sorted(values, key=lambda value: value.identifier)
        kept_ids.add(ordered[0].identifier)
        if len(ordered) > 1:
            removed_groups.append({
                "kept_id": ordered[0].identifier,
                "removed_ids": [value.identifier for value in ordered[1:]],
            })
    removed_groups.sort(key=lambda value: value["kept_id"])
    return (
        [segment for segment in segments if segment.identifier in kept_ids],
        {
            "removed_segment_count": sum(
                len(value["removed_ids"]) for value in removed_groups
            ),
            "removed_geometry_groups": removed_groups[:25],
        },
    )


def endpoint_id(original_node_id: int, clipped: tuple[float, float], original: tuple[float, float]) -> int:
    if abs(clipped[0] - original[0]) < 1e-9 and abs(clipped[1] - original[1]) < 1e-9:
        return original_node_id
    digest = hashlib.sha256(f"{clipped[0]:.7f},{clipped[1]:.7f}".encode()).digest()
    return -int.from_bytes(digest[:7], "big")


def geodesic_polyline_length(coordinates: tuple[tuple[float, float], ...]) -> float:
    from math import asin, cos, radians, sin, sqrt

    total = 0.0
    radius = 6_371_008.8
    for (lon1, lat1), (lon2, lat2) in zip(coordinates, coordinates[1:]):
        latitude_delta = radians(lat2 - lat1)
        longitude_delta = radians(lon2 - lon1)
        a = sin(latitude_delta / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(longitude_delta / 2) ** 2
        total += radius * 2 * asin(sqrt(min(1.0, a)))
    return total


def write_database(path: Path, metadata: dict[str, str], segments: list[Segment]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.unlink()
    connection = sqlite3.connect(path)
    try:
        connection.executescript("""
            PRAGMA journal_mode = DELETE;
            PRAGMA synchronous = FULL;
            CREATE TABLE metadata (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            );
            CREATE TABLE segments (
                rowid INTEGER PRIMARY KEY,
                id TEXT UNIQUE NOT NULL,
                start_node INTEGER NOT NULL,
                end_node INTEGER NOT NULL,
                kind TEXT NOT NULL,
                length_meters REAL NOT NULL,
                source_way_id INTEGER,
                name TEXT,
                coordinates_json BLOB NOT NULL,
                counts_toward_coverage INTEGER NOT NULL,
                layer INTEGER NOT NULL,
                bridge INTEGER NOT NULL,
                tunnel INTEGER NOT NULL,
                min_longitude REAL NOT NULL,
                max_longitude REAL NOT NULL,
                min_latitude REAL NOT NULL,
                max_latitude REAL NOT NULL
            );
            CREATE VIRTUAL TABLE segment_rtree USING rtree(
                rowid, min_longitude, max_longitude, min_latitude, max_latitude
            );
            CREATE TABLE adjacency (
                node_id INTEGER NOT NULL,
                neighbor_node_id INTEGER NOT NULL,
                segment_id TEXT NOT NULL,
                length_meters REAL NOT NULL
            );
            CREATE INDEX adjacency_node_index ON adjacency(node_id);
        """)
        connection.executemany(
            "INSERT INTO metadata(key, value) VALUES (?, ?)",
            sorted(metadata.items()),
        )
        for segment in sorted(segments, key=lambda value: value.identifier):
            longitudes = [coordinate[0] for coordinate in segment.coordinates]
            latitudes = [coordinate[1] for coordinate in segment.coordinates]
            cursor = connection.execute(
                """
                INSERT INTO segments(
                    id, start_node, end_node, kind, length_meters, source_way_id,
                    name, coordinates_json, counts_toward_coverage, layer, bridge, tunnel,
                    min_longitude, max_longitude, min_latitude, max_latitude
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    segment.identifier,
                    segment.start_node,
                    segment.end_node,
                    segment.kind,
                    segment.length_meters,
                    segment.source_way_id,
                    segment.name,
                    json.dumps(segment.coordinates, separators=(",", ":")).encode(),
                    1 if segment.counts_toward_coverage else 0,
                    segment.layer,
                    1 if segment.bridge else 0,
                    1 if segment.tunnel else 0,
                    min(longitudes),
                    max(longitudes),
                    min(latitudes),
                    max(latitudes),
                ),
            )
            rowid = cursor.lastrowid
            connection.execute(
                "INSERT INTO segment_rtree VALUES (?, ?, ?, ?, ?)",
                (rowid, min(longitudes), max(longitudes), min(latitudes), max(latitudes)),
            )
            connection.executemany(
                "INSERT INTO adjacency VALUES (?, ?, ?, ?)",
                [
                    (segment.start_node, segment.end_node, segment.identifier, segment.length_meters),
                    (segment.end_node, segment.start_node, segment.identifier, segment.length_meters),
                ],
            )
        connection.commit()
        connection.execute("VACUUM")
    finally:
        connection.close()


def pbf_source_date(path: Path) -> str:
    reader = osmium.io.Reader(str(path))
    try:
        timestamp = reader.header().get("osmosis_replication_timestamp")
    finally:
        reader.close()
    return timestamp or datetime.fromtimestamp(path.stat().st_mtime, UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def component_groups(segments: list[Segment]) -> list[list[Segment]]:
    parents: dict[int, int] = {}

    def find(node: int) -> int:
        parents.setdefault(node, node)
        while parents[node] != node:
            parents[node] = parents[parents[node]]
            node = parents[node]
        return node

    def union(first: int, second: int) -> None:
        first_root = find(first)
        second_root = find(second)
        if first_root != second_root:
            parents[second_root] = first_root

    for segment in segments:
        union(segment.start_node, segment.end_node)

    grouped: dict[int, list[Segment]] = defaultdict(list)
    for segment in segments:
        grouped[find(segment.start_node)].append(segment)
    return sorted(
        grouped.values(),
        key=lambda values: sum(
            segment.length_meters
            for segment in values
            if segment.counts_toward_coverage
        ),
        reverse=True,
    )


def component_size_bucket(segment_count: int) -> str:
    if segment_count == 1:
        return "1"
    if segment_count <= 5:
        return "2-5"
    if segment_count <= 20:
        return "6-20"
    if segment_count <= 100:
        return "21-100"
    if segment_count <= 1_000:
        return "101-1000"
    return "1001+"


def connectivity_stats(segments: list[Segment]) -> dict[str, Any]:
    components = component_groups(segments)
    if not components:
        return {
            "component_count": 0,
            "component_size_histogram": {},
            "largest_components": [],
            "largest_component_goal_length_miles": 0,
            "largest_component_goal_percent": 0,
            "largest_component_goal_segment_count": 0,
            "largest_component_total_segment_count": 0,
        }

    total_goal_length = sum(
        segment.length_meters for segment in segments if segment.counts_toward_coverage
    )
    largest = components[0]
    largest_goal = [segment for segment in largest if segment.counts_toward_coverage]
    largest_length = sum(segment.length_meters for segment in largest_goal)
    histogram = Counter(component_size_bucket(len(component)) for component in components)
    component_details = []
    for rank, component in enumerate(components[:25], start=1):
        goal_segments = [segment for segment in component if segment.counts_toward_coverage]
        coordinates = [coordinate for segment in component for coordinate in segment.coordinates]
        component_details.append({
            "rank": rank,
            "goal_length_miles": sum(segment.length_meters for segment in goal_segments) / 1_609.344,
            "goal_segment_count": len(goal_segments),
            "total_segment_count": len(component),
            "named_goal_segment_count": sum(1 for segment in goal_segments if segment.name),
            "unnamed_goal_segment_count": sum(1 for segment in goal_segments if not segment.name),
            "kinds": dict(Counter(segment.kind for segment in goal_segments)),
            "bounding_box": {
                "min_longitude": min(value[0] for value in coordinates),
                "min_latitude": min(value[1] for value in coordinates),
                "max_longitude": max(value[0] for value in coordinates),
                "max_latitude": max(value[1] for value in coordinates),
            },
        })
    return {
        "component_count": len(components),
        "component_size_histogram": dict(sorted(histogram.items())),
        "largest_components": component_details,
        "largest_component_goal_length_miles": largest_length / 1_609.344,
        "largest_component_goal_percent": (
            largest_length / total_goal_length * 100 if total_goal_length else 0
        ),
        "largest_component_goal_segment_count": len(largest_goal),
        "largest_component_total_segment_count": len(largest),
    }


def named_goal_miles_by_kind(segments: list[Segment]) -> dict[str, dict[str, float]]:
    result: dict[str, dict[str, float]] = {}
    for kind in sorted({segment.kind for segment in segments}):
        goal = [
            segment
            for segment in segments
            if segment.kind == kind and segment.counts_toward_coverage
        ]
        named = sum(segment.length_meters for segment in goal if segment.name) / 1_609.344
        unnamed = sum(segment.length_meters for segment in goal if not segment.name) / 1_609.344
        result[kind] = {
            "named_miles": named,
            "unnamed_miles": unnamed,
            "total_miles": named + unnamed,
        }
    return result


def geometry_audit(
    segments: list[Segment],
    boundary: Polygon,
    tolerance_degrees: float = 1e-8,
) -> dict[str, Any]:
    buffered_boundary = boundary.buffer(tolerance_degrees)
    invalid_ids: list[str] = []
    outside_ids: list[str] = []
    identifiers = Counter(segment.identifier for segment in segments)
    geometry_identifiers: dict[tuple[tuple[float, float], ...], list[str]] = defaultdict(list)

    for segment in segments:
        finite = all(math.isfinite(value) for coordinate in segment.coordinates for value in coordinate)
        line = LineString(segment.coordinates) if len(segment.coordinates) >= 2 else None
        if (
            not finite
            or line is None
            or line.is_empty
            or not line.is_valid
            or segment.length_meters <= 0
        ):
            invalid_ids.append(segment.identifier)
            continue
        if not buffered_boundary.covers(line):
            outside_ids.append(segment.identifier)
        geometry_identifiers[canonical_geometry(segment.coordinates)].append(segment.identifier)

    duplicate_identifiers = sorted(key for key, count in identifiers.items() if count > 1)
    duplicate_geometry_groups = [
        identifiers
        for identifiers in geometry_identifiers.values()
        if len(identifiers) > 1
    ]
    duplicate_geometry_count = sum(len(values) - 1 for values in duplicate_geometry_groups)
    return {
        "boundary_tolerance_degrees": tolerance_degrees,
        "all_segments_within_boundary": not outside_ids,
        "outside_boundary_count": len(outside_ids),
        "outside_boundary_sample_ids": outside_ids[:25],
        "invalid_geometry_count": len(invalid_ids),
        "invalid_geometry_sample_ids": invalid_ids[:25],
        "duplicate_identifier_count": len(duplicate_identifiers),
        "duplicate_identifier_sample_ids": duplicate_identifiers[:25],
        "duplicate_geometry_count": duplicate_geometry_count,
        "duplicate_geometry_sample_id_groups": duplicate_geometry_groups[:25],
    }


def topology_audit(segments: list[Segment]) -> dict[str, Any]:
    by_node: dict[int, list[Segment]] = defaultdict(list)
    for segment in segments:
        by_node[segment.start_node].append(segment)
        by_node[segment.end_node].append(segment)
    shared = {node: values for node, values in by_node.items() if len(values) > 1}

    def sample_nodes(predicate: Callable[[list[Segment]], bool]) -> list[int]:
        return sorted(node for node, values in shared.items() if predicate(values))[:25]

    mixed_layer = sample_nodes(lambda values: len({segment.layer for segment in values}) > 1)
    mixed_bridge = sample_nodes(lambda values: len({segment.bridge for segment in values}) > 1)
    mixed_tunnel = sample_nodes(lambda values: len({segment.tunnel for segment in values}) > 1)
    return {
        "shared_node_count": len(shared),
        "self_loop_segment_count": sum(
            1 for segment in segments if segment.start_node == segment.end_node
        ),
        "self_loop_segment_sample_ids": [
            segment.identifier
            for segment in segments
            if segment.start_node == segment.end_node
        ][:25],
        "layer_tagged_segment_count": sum(1 for segment in segments if segment.layer != 0),
        "bridge_segment_count": sum(1 for segment in segments if segment.bridge),
        "tunnel_segment_count": sum(1 for segment in segments if segment.tunnel),
        "mixed_layer_shared_node_count": sum(
            1 for values in shared.values() if len({segment.layer for segment in values}) > 1
        ),
        "mixed_layer_shared_node_samples": mixed_layer,
        "mixed_bridge_shared_node_count": sum(
            1 for values in shared.values() if len({segment.bridge for segment in values}) > 1
        ),
        "mixed_bridge_shared_node_samples": mixed_bridge,
        "mixed_tunnel_shared_node_count": sum(
            1 for values in shared.values() if len({segment.tunnel for segment in values}) > 1
        ),
        "mixed_tunnel_shared_node_samples": mixed_tunnel,
    }


def write_review_geojson(path: Path, segments: list[Segment], limit: int = 5_000) -> dict[str, int]:
    components = component_groups(segments)
    component_rank: dict[str, int] = {}
    component_miles: dict[str, float] = {}
    for rank, component in enumerate(components, start=1):
        miles = sum(
            segment.length_meters
            for segment in component
            if segment.counts_toward_coverage
        ) / 1_609.344
        for segment in component:
            component_rank[segment.identifier] = rank
            component_miles[segment.identifier] = miles

    suspicious = [
        segment
        for segment in segments
        if segment.counts_toward_coverage
        and (
            not segment.name
            or component_rank.get(segment.identifier, 1) > 1
        )
    ]
    suspicious.sort(key=lambda value: (
        component_rank.get(value.identifier, 1) == 1,
        value.name is not None,
        -value.length_meters,
    ))
    features = []
    for segment in suspicious[:limit]:
        reasons = []
        if not segment.name:
            reasons.append("unnamed")
        if component_rank.get(segment.identifier, 1) > 1:
            reasons.append("disconnected_component")
        features.append({
            "type": "Feature",
            "geometry": mapping(LineString(segment.coordinates)),
            "properties": {
                "segment_id": segment.identifier,
                "source_way_id": segment.source_way_id,
                "name": segment.name,
                "kind": segment.kind,
                "length_meters": segment.length_meters,
                "component_rank": component_rank.get(segment.identifier),
                "component_goal_miles": component_miles.get(segment.identifier),
                "reasons": reasons,
            },
        })
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"type": "FeatureCollection", "features": features}, indent=2) + "\n")
    return {
        "suspicious_segment_count": len(suspicious),
        "review_feature_count": len(features),
        "review_feature_limit": limit,
    }


def build(args: argparse.Namespace) -> None:
    boundary = load_largest_polygon(args.boundary)
    counter = IntersectionCounter(boundary)
    counter.apply_file(str(args.input_pbf), locations=True, idx="flex_mem")
    intersections = {node_id for node_id, count in counter.node_use.items() if count > 1}

    collector = SegmentCollector(boundary, intersections)
    collector.apply_file(str(args.input_pbf), locations=True, idx="flex_mem")
    segments, deduplication = deduplicate_segments(collector.segments)
    source_checksum = file_sha256(args.input_pbf)
    boundary_checksum = file_sha256(args.boundary)
    source_date = args.source_date or pbf_source_date(args.input_pbf)
    metadata = {
        "identifier": args.identifier,
        "display_name": args.display_name,
        "version": str(args.version),
        "source_date": source_date,
        "source_url": args.source_url,
        "source_sha256": source_checksum,
        "boundary_url": args.boundary_url,
        "boundary_sha256": boundary_checksum,
        "attribution": "© OpenStreetMap contributors, ODbL 1.0",
        "builder_schema_version": "3",
        "exclusions_scope": "largest Manhattan borough polygon",
    }
    write_database(args.output, metadata, segments)

    total_length = sum(
        segment.length_meters
        for segment in segments
        if segment.counts_toward_coverage
    )
    geometry = geometry_audit(segments, boundary)
    review = (
        write_review_geojson(args.review_geojson, segments)
        if args.review_geojson is not None
        else None
    )
    report: dict[str, Any] = {
        "metadata": metadata,
        "segment_count": len(segments),
        "total_length_meters": total_length,
        "total_length_miles": total_length / 1_609.344,
        "kinds": dict(Counter(segment.kind for segment in segments)),
        "goal_length_miles_by_kind": {
            kind: sum(
                segment.length_meters
                for segment in segments
                if segment.kind == kind and segment.counts_toward_coverage
            ) / 1_609.344
            for kind in sorted({segment.kind for segment in segments})
        },
        "goal_miles_named_and_unnamed_by_kind": named_goal_miles_by_kind(
            segments
        ),
        "graph_only_segment_count": sum(
            1 for segment in segments if not segment.counts_toward_coverage
        ),
        "excluded_ways_in_manhattan_boundary": dict(
            counter.exclusions + collector.exclusions
        ),
        "geometry_audit": geometry,
        "deduplication": deduplication,
        "topology_audit": topology_audit(segments),
        "connectivity": connectivity_stats(segments),
    }
    if review is not None:
        report["review_geojson"] = review
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    if not geometry["all_segments_within_boundary"]:
        raise ValueError("Generated segments extend beyond the Manhattan boundary tolerance")
    if geometry["invalid_geometry_count"]:
        raise ValueError("Generated map contains invalid segment geometry")
    if geometry["duplicate_identifier_count"]:
        raise ValueError("Generated map contains duplicate segment identifiers")
    if geometry["duplicate_geometry_count"]:
        raise ValueError("Generated map contains duplicate segment geometry")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-pbf", type=Path, required=True)
    parser.add_argument("--boundary", type=Path, required=True)
    parser.add_argument(
        "--boundary-url",
        default="https://data.cityofnewyork.us/resource/gthc-hcne.geojson",
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--review-geojson", type=Path)
    parser.add_argument("--identifier", default="manhattan-island")
    parser.add_argument("--display-name", default="Manhattan Island")
    parser.add_argument("--version", type=int, default=2)
    parser.add_argument(
        "--source-url",
        default="https://download.geofabrik.de/north-america/us/new-york-260825.osm.pbf",
    )
    parser.add_argument("--source-date")
    return parser.parse_args()


def main() -> None:
    build(parse_args())


if __name__ == "__main__":
    main()
