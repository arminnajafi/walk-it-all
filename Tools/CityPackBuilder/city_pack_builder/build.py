from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
from datetime import UTC, datetime
import hashlib
import json
from pathlib import Path
import sqlite3
from typing import Iterable

import osmium
from shapely.geometry import LineString, MultiLineString, Polygon, shape


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
    def __init__(self) -> None:
        super().__init__()
        self.node_use: Counter[int] = Counter()
        self.exclusions: Counter[str] = Counter()

    def way(self, way: osmium.osm.Way) -> None:
        tags = {tag.k: tag.v for tag in way.tags}
        eligibility = classify_way(tags)
        if not eligibility.included:
            self.exclusions[eligibility.reason] += 1
            return
        self.node_use.update(node.ref for node in way.nodes)


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
                ))


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
                    name, coordinates_json, counts_toward_coverage, min_longitude, max_longitude,
                    min_latitude, max_latitude
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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


def connectivity_stats(segments: list[Segment]) -> dict[str, float | int]:
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

    goal_length_by_component: dict[int, float] = {}
    goal_segments_by_component: Counter[int] = Counter()
    all_segments_by_component: Counter[int] = Counter()
    for segment in segments:
        root = find(segment.start_node)
        all_segments_by_component[root] += 1
        if segment.counts_toward_coverage:
            goal_length_by_component[root] = goal_length_by_component.get(root, 0) + segment.length_meters
            goal_segments_by_component[root] += 1

    total_goal_length = sum(goal_length_by_component.values())
    largest_root = max(goal_length_by_component, key=goal_length_by_component.get) if goal_length_by_component else None
    largest_length = goal_length_by_component.get(largest_root, 0) if largest_root is not None else 0
    return {
        "component_count": len(all_segments_by_component),
        "largest_component_goal_length_miles": largest_length / 1_609.344,
        "largest_component_goal_percent": (
            largest_length / total_goal_length * 100 if total_goal_length else 0
        ),
        "largest_component_goal_segment_count": (
            goal_segments_by_component[largest_root] if largest_root is not None else 0
        ),
        "largest_component_total_segment_count": (
            all_segments_by_component[largest_root] if largest_root is not None else 0
        ),
    }


def build(args: argparse.Namespace) -> None:
    boundary = load_largest_polygon(args.boundary)
    counter = IntersectionCounter()
    counter.apply_file(str(args.input_pbf), locations=False)
    intersections = {node_id for node_id, count in counter.node_use.items() if count > 1}

    collector = SegmentCollector(boundary, intersections)
    collector.apply_file(str(args.input_pbf), locations=True, idx="flex_mem")
    source_checksum = hashlib.sha256(args.input_pbf.read_bytes()).hexdigest()
    boundary_checksum = hashlib.sha256(args.boundary.read_bytes()).hexdigest()
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
        "generated_at": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    write_database(args.output, metadata, collector.segments)

    total_length = sum(
        segment.length_meters
        for segment in collector.segments
        if segment.counts_toward_coverage
    )
    report = {
        "metadata": metadata,
        "segment_count": len(collector.segments),
        "total_length_meters": total_length,
        "total_length_miles": total_length / 1_609.344,
        "kinds": dict(Counter(segment.kind for segment in collector.segments)),
        "goal_length_miles_by_kind": {
            kind: sum(
                segment.length_meters
                for segment in collector.segments
                if segment.kind == kind and segment.counts_toward_coverage
            ) / 1_609.344
            for kind in sorted({segment.kind for segment in collector.segments})
        },
        "graph_only_segment_count": sum(
            1 for segment in collector.segments if not segment.counts_toward_coverage
        ),
        "excluded_ways": dict(counter.exclusions + collector.exclusions),
        "connectivity": connectivity_stats(collector.segments),
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")


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
    parser.add_argument("--identifier", default="manhattan-island")
    parser.add_argument("--display-name", default="Manhattan Island")
    parser.add_argument("--version", type=int, default=1)
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
