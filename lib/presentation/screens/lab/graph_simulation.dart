import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../../domain/models/graph.dart';

enum GraphLayoutMode { solar, knowledge }

/// Visual radius (world units) of a node by kind. Shared by the simulation
/// (collision) and the painter so spacing and drawing stay consistent.
double graphNodeRadius(GraphNodeKind k) => switch (k) {
      GraphNodeKind.space => 46,
      GraphNodeKind.folder => 28,
      GraphNodeKind.card => 22,
      GraphNodeKind.note => 18,
      GraphNodeKind.task => 15,
      GraphNodeKind.url => 14,
    };

/// Live force-directed simulation (D3-style): nodes settle on load and, when a
/// node is dragged, the whole graph follows it with springs ("jala todo el
/// grafo"). A position-based collision pass guarantees nodes never overlap (so
/// it never looks "super pegado"). Heat-aware: [alpha] cools toward 0 and
/// [step] reports when cold so the widget STOPS ticking (no physics at rest).
///
/// Deterministic: same graph + [seed] → same settled layout.
class GraphSimulation {
  /// [previous] carries over positions from an earlier simulation (real-time
  /// data updates): nodes that still exist keep their place and the layout only
  /// nudges (low [alpha]) instead of re-exploding from scratch.
  GraphSimulation(this.data,
      {int seed = 7,
      Map<String, Offset>? previous,
      this.layout = GraphLayoutMode.solar}) {
    final rnd = math.Random(seed);
    for (final n in data.nodes) {
      _kind[n.id] = n.kind;
      _radius[n.id] = graphNodeRadius(n.kind);
    }
    _computeAnchors();

    // Structured seeding (avoids the "starts tangled in the centre" local
    // minimum): folders ring the sun, each node spawns around its anchor so the
    // regions exist from frame 0 and the settle only tightens them.
    final roots = data.nodes.where((n) => n.isRoot).toList();
    final sib = <String, int>{};
    final ordered = [...data.nodes]
      ..sort((a, b) => _seedDepth(a.kind).compareTo(_seedDepth(b.kind)));
    for (final n in ordered) {
      if (n.isRoot) {
        final idx = roots.indexOf(n);
        final at = roots.length == 1
            ? Offset.zero
            : Offset(math.cos(2 * math.pi * idx / roots.length),
                    math.sin(2 * math.pi * idx / roots.length)) *
                (_baseLinkDist * 4);
        _bodies[n.id] = _Body(at, root: true);
        continue;
      }
      if (previous != null && previous.containsKey(n.id)) {
        _bodies[n.id] = _Body(previous[n.id]!);
        continue;
      }
      final anchorId = _anchor[n.id];
      final base = (anchorId != null && _bodies[anchorId] != null)
          ? _bodies[anchorId]!.pos
          : Offset.zero;
      final key = anchorId ?? '_root';
      final idx = sib[key] = (sib[key] ?? 0) + 1;
      final ang = 2 * math.pi * 0.618 * idx + rnd.nextDouble() * 0.4;
      final rr = layout == GraphLayoutMode.knowledge
          ? 54 + math.sqrt(idx) * 28 + rnd.nextDouble() * 18
          : _seedRadius(n.kind) + (rnd.nextDouble() - 0.5) * 24;
      _bodies[n.id] = _Body(base + Offset(math.cos(ang), math.sin(ang)) * rr);
    }
    // The structured seed already looks right (separated regions). Use a LOW
    // alpha so the settle only relaxes overlaps via collision instead of a full
    // re-layout that collapses everything inward. Carry-over relaxes even less.
    alpha = previous != null
        ? (layout == GraphLayoutMode.knowledge ? 0.34 : 0.28)
        : (layout == GraphLayoutMode.knowledge ? 0.58 : 0.42);
  }

  static int _seedDepth(GraphNodeKind k) => switch (k) {
        GraphNodeKind.space => 0,
        GraphNodeKind.folder || GraphNodeKind.card => 1,
        GraphNodeKind.note || GraphNodeKind.url => 2,
        GraphNodeKind.task => 3,
      };

  static double _seedRadius(GraphNodeKind k) => switch (k) {
        GraphNodeKind.folder => 261, // sun spoke ×0.9
        GraphNodeKind.card => 162, // sun spoke ×0.9
        GraphNodeKind.note => 88, // intra-cluster (unchanged)
        GraphNodeKind.task => 58,
        GraphNodeKind.url => 88,
        GraphNodeKind.space => 0,
      };

  final GraphData data;
  final GraphLayoutMode layout;
  final Map<String, _Body> _bodies = {};
  final Map<String, double> _radius = {};
  final Map<String, GraphNodeKind> _kind = {};

  /// Layout "parent" each node orbits — the heart of readable REGIONS: notes
  /// hug their folder, tasks hug their note/folder, folders + cards hug the sun.
  final Map<String, String?> _anchor = {};

  // Tuned to the reference: long sun→folder spokes (each folder owns a region),
  // short intra-cluster links, strong separation, never overlapping.
  static const double _baseLinkDist = 130;
  static const double _linkStrength = 0.35;
  static const double _charge = 9500; // repulsion → whitespace + region split
  static const double _clusterPull = 0.05; // gentle: seed already groups regions
  static const double _gravity = 0.004; // tiny pull to origin (anti-drift)
  static const double _collidePad = 16;
  static const double _velocityDecay = 0.62;
  static const double _alphaDecay = 0.03;
  static const double _alphaMin = 0.02;
  static const double _maxVel = 70;

  /// Per-edge rest length: long spokes from the sun (so folders get their own
  /// neighbourhood), short links inside a folder's cluster.
  double _linkDistFor(GraphEdge e) {
    if (layout == GraphLayoutMode.knowledge) return 108;
    final a = _kind[e.from];
    final b = _kind[e.to];
    bool has(GraphNodeKind k) => a == k || b == k;
    if (has(GraphNodeKind.space)) {
      // Sun spokes scaled 0.9× of the original (300/200); intra-cluster compact.
      return has(GraphNodeKind.folder) ? 270 : 180;
    }
    if (has(GraphNodeKind.folder)) return 86; // folder → note
    return 60; // note↔task, card↔task, ai note↔note
  }

  /// Each node's cluster anchor, derived from the edges (order-independent):
  /// folder/card → the sun; note → its folder (else sun); task → its folder
  /// (else its note, else its card). Drives the cluster-gravity force.
  void _computeAnchors() {
    if (layout == GraphLayoutMode.knowledge) {
      for (final n in data.nodes) {
        _anchor[n.id] = null;
      }
      return;
    }
    final adj = <String, List<String>>{
      for (final n in data.nodes) n.id: <String>[]
    };
    for (final e in data.edges) {
      adj[e.from]?.add(e.to);
      adj[e.to]?.add(e.from);
    }
    String? neighborOf(String id, GraphNodeKind k) {
      for (final x in adj[id] ?? const <String>[]) {
        if (_kind[x] == k) return x;
      }
      return null;
    }

    for (final n in data.nodes) {
      _anchor[n.id] = switch (n.kind) {
        GraphNodeKind.space => null,
        GraphNodeKind.folder ||
        GraphNodeKind.card =>
          neighborOf(n.id, GraphNodeKind.space),
        GraphNodeKind.note => neighborOf(n.id, GraphNodeKind.folder) ??
            neighborOf(n.id, GraphNodeKind.space),
        GraphNodeKind.task => neighborOf(n.id, GraphNodeKind.folder) ??
            neighborOf(n.id, GraphNodeKind.note) ??
            neighborOf(n.id, GraphNodeKind.card),
        GraphNodeKind.url => null,
      };
    }
  }

  double alpha = 1.0;

  /// While true (a node is being dragged) the GLOBAL forces (pull to origin +
  /// cluster gravity) are off, so only edge springs propagate the motion: the
  /// dragged node moves its connected neighbours and nothing else. Full forces
  /// resume on release so the graph re-settles cleanly.
  bool dragActive = false;

  Offset? posOf(String id) => _bodies[id]?.pos;
  Map<String, Offset> get positions =>
      {for (final e in _bodies.entries) e.key: e.value.pos};

  void reheat([double a = 0.5]) => alpha = math.max(alpha, a);

  void pin(String id, Offset world) {
    final b = _bodies[id];
    if (b == null) return;
    b.pinned = true;
    b.pos = world;
    b.vel = Offset.zero;
  }

  void movePinned(String id, Offset world) => _bodies[id]?.pos = world;
  void unpin(String id) => _bodies[id]?.pinned = false;

  /// One integration step. Returns true while still "hot" (keep ticking).
  bool step() {
    if (alpha < _alphaMin) return false;
    alpha += (0 - alpha) * _alphaDecay;
    final nodes = data.nodes;
    final n = nodes.length;

    // Repulsion (all pairs) — OFF during a drag so untethered nodes stay put.
    if (!dragActive) {
      for (var i = 0; i < n; i++) {
        final a = _bodies[nodes[i].id]!;
        for (var j = i + 1; j < n; j++) {
          final b = _bodies[nodes[j].id]!;
          var dx = a.pos.dx - b.pos.dx;
          var dy = a.pos.dy - b.pos.dy;
          var d2 = dx * dx + dy * dy;
          if (d2 < 16) {
            dx = (i - j).isEven ? 1.0 : -1.0;
            dy = 0.7;
            d2 = 16;
          }
          final d = math.sqrt(d2);
          final charge =
              layout == GraphLayoutMode.knowledge ? 7200.0 : _charge;
          final f = charge * alpha / d2;
          a.vel += Offset(dx / d * f, dy / d * f);
          b.vel -= Offset(dx / d * f, dy / d * f);
        }
      }
    }

    // Springs (edges).
    for (final e in data.edges) {
      final a = _bodies[e.from];
      final b = _bodies[e.to];
      if (a == null || b == null) continue;
      var dx = b.pos.dx - a.pos.dx;
      var dy = b.pos.dy - a.pos.dy;
      final d = math.max(math.sqrt(dx * dx + dy * dy), 1.0);
      final diff = (d - _linkDistFor(e)) / d * _linkStrength * alpha;
      a.vel += Offset(dx * diff * 0.5, dy * diff * 0.5);
      b.vel -= Offset(dx * diff * 0.5, dy * diff * 0.5);
    }

    // Cluster gravity (children → their anchor) + origin gravity + integrate.
    for (final nd in nodes) {
      final b = _bodies[nd.id]!;
      if (b.root || b.pinned) {
        b.vel = Offset.zero;
        continue;
      }
      // Global forces (cluster + origin gravity) are OFF during a drag, so
      // dragging a node only propagates through edge springs to its connected
      // neighbours — unconnected nodes stay put.
      if (!dragActive) {
        final anchorId = _anchor[nd.id];
        if (anchorId != null) {
          final ap = _bodies[anchorId];
          if (ap != null) {
            b.vel += Offset(ap.pos.dx - b.pos.dx, ap.pos.dy - b.pos.dy) *
                (_clusterPull * alpha);
          }
        }
        final gravity =
            layout == GraphLayoutMode.knowledge ? 0.007 : _gravity;
        b.vel += Offset(-b.pos.dx, -b.pos.dy) * (gravity * alpha);
      }
      var v = b.vel * _velocityDecay;
      v = Offset(v.dx.clamp(-_maxVel, _maxVel), v.dy.clamp(-_maxVel, _maxVel));
      b.vel = v;
      b.pos += v;
    }

    _resolveCollisions(nodes);
    return alpha >= _alphaMin;
  }

  /// Position-based separation so two nodes never overlap (D3 forceCollide).
  void _resolveCollisions(List<GraphNode> nodes) {
    final n = nodes.length;
    for (var iter = 0; iter < 2; iter++) {
      for (var i = 0; i < n; i++) {
        final a = _bodies[nodes[i].id]!;
        final ra = _radius[nodes[i].id]!;
        for (var j = i + 1; j < n; j++) {
          final b = _bodies[nodes[j].id]!;
          final rb = _radius[nodes[j].id]!;
          final minD = ra + rb + _pairCollidePad(nodes[i].kind, nodes[j].kind);
          var dx = a.pos.dx - b.pos.dx;
          var dy = a.pos.dy - b.pos.dy;
          var d = math.sqrt(dx * dx + dy * dy);
          if (d == 0) {
            dx = 1;
            dy = 0;
            d = 1;
          }
          if (d >= minD) continue;
          final push = (minD - d) / d * 0.5;
          final shift = Offset(dx * push, dy * push);
          final aFixed = a.root || a.pinned;
          final bFixed = b.root || b.pinned;
          if (aFixed && bFixed) continue;
          if (aFixed) {
            b.pos -= shift * 2;
          } else if (bFixed) {
            a.pos += shift * 2;
          } else {
            a.pos += shift;
            b.pos -= shift;
          }
        }
      }
    }
  }

  Map<String, Offset> settle({int maxSteps = 600}) {
    var i = 0;
    while (i++ < maxSteps && step()) {}
    return positions;
  }

  double _pairCollidePad(GraphNodeKind a, GraphNodeKind b) {
    if (a == GraphNodeKind.note && b == GraphNodeKind.note) return 24;
    if (a == GraphNodeKind.task && b == GraphNodeKind.task) return 24;
    if ((a == GraphNodeKind.note && b == GraphNodeKind.task) ||
        (a == GraphNodeKind.task && b == GraphNodeKind.note)) {
      return 26;
    }
    if ((a == GraphNodeKind.note &&
            (b == GraphNodeKind.folder || b == GraphNodeKind.card)) ||
        (b == GraphNodeKind.note &&
            (a == GraphNodeKind.folder || a == GraphNodeKind.card))) {
      return 20;
    }
    if ((a == GraphNodeKind.task &&
            (b == GraphNodeKind.folder || b == GraphNodeKind.card)) ||
        (b == GraphNodeKind.task &&
            (a == GraphNodeKind.folder || a == GraphNodeKind.card))) {
      return 20;
    }
    return _collidePad;
  }
}

class _Body {
  _Body(this.pos, {this.root = false});
  Offset pos;
  Offset vel = Offset.zero;
  bool pinned = false;
  final bool root;
}
