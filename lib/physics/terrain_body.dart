import 'package:flame_forge2d/flame_forge2d.dart';

/// Static collision body generated from marching squares mesh vertices
///
/// Each chunk produces a set of edge/chain shapes that form the
/// collision boundaries between solid and empty terrain.
class TerrainBody extends BodyComponent {
  final Vector2 chunkPosition;
  final List<List<Vector2>> edgeSegments;

  TerrainBody({
    required this.chunkPosition,
    required this.edgeSegments,
  });

  @override
  Body createBody() {
    final bodyDef = BodyDef(
      type: BodyType.static,
      position: chunkPosition,
    );

    final body = world.createBody(bodyDef);

    for (final segment in edgeSegments) {
      if (segment.length < 2) continue;

      if (segment.length == 2) {
        final edge = EdgeShape()..set(segment[0], segment[1]);
        body.createFixture(FixtureDef(edge)
          ..friction = 0.3
          ..restitution = 0.0
          ..userData = 'terrain');
      } else {
        final chain = ChainShape()..createChain(segment);
        body.createFixture(FixtureDef(chain)
          ..friction = 0.3
          ..restitution = 0.0
          ..userData = 'terrain');
      }
    }

    return body;
  }

  /// Rebuild all fixtures (after terrain modification)
  void rebuildFixtures(List<List<Vector2>> newSegments) {
    // Remove existing fixtures
    while (body.fixtures.isNotEmpty) {
      body.destroyFixture(body.fixtures.first);
    }

    // Create new fixtures
    for (final segment in newSegments) {
      if (segment.length < 2) continue;

      if (segment.length == 2) {
        final edge = EdgeShape()..set(segment[0], segment[1]);
        body.createFixture(FixtureDef(edge)
          ..friction = 0.3
          ..restitution = 0.0
          ..userData = 'terrain');
      } else {
        final chain = ChainShape()..createChain(segment);
        body.createFixture(FixtureDef(chain)
          ..friction = 0.3
          ..restitution = 0.0
          ..userData = 'terrain');
      }
    }
  }
}
