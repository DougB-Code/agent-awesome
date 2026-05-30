/// Home workspace system diagram widgets and painter.
part of 'workspace_widgets.dart';

/// _AgentSystemDiagram renders the orbital system diagram from the screenshot.
class _AgentSystemDiagram extends StatelessWidget {
  /// Creates the hero diagram.
  const _AgentSystemDiagram({required this.compact});

  /// Whether to use the compact label placement.
  final bool compact;

  /// Builds the diagram using lightweight Flutter primitives.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, compact ? 320.0 : 520.0);
        return Center(
          child: SizedBox.square(
            dimension: side,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(painter: _OrbitPainter(colors: colors)),
                ),
                _LayeredAgentCore(colors: colors),
                _OrbitLabel(label: 'AI', left: side * 0.12, top: 0),
                _OrbitLabel(label: 'CLI', left: side * 0.26, top: side * 0.18),
                _OrbitLabel(
                  label: 'MCP',
                  right: compact ? side * 0.02 : side * 0.00,
                  top: side * 0.30,
                ),
                _OrbitLabel(
                  label: 'API',
                  left: side * 0.12,
                  bottom: side * 0.30,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// _OrbitLabel renders one floating capability label.
class _OrbitLabel extends StatelessWidget {
  /// Creates a positioned orbit label.
  const _OrbitLabel({
    required this.label,
    this.left,
    this.right,
    this.top,
    this.bottom,
  });

  /// Label text.
  final String label;

  /// Left position.
  final double? left;

  /// Right position.
  final double? right;

  /// Top position.
  final double? top;

  /// Bottom position.
  final double? bottom;

  /// Builds the floating label.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: colors.green,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

/// _LayeredAgentCore renders the isometric stack at the diagram center.
class _LayeredAgentCore extends StatelessWidget {
  /// Creates the layered center mark.
  const _LayeredAgentCore({required this.colors});

  /// Active semantic color palette.
  final AgentAwesomePalette colors;

  /// Builds the stacked layers and coral diamond.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      height: 210,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          _IsometricLayer(
            colors: colors,
            offset: const Offset(0, 58),
            opacity: 0.34,
          ),
          _IsometricLayer(
            colors: colors,
            offset: const Offset(0, 28),
            opacity: 0.50,
          ),
          _IsometricLayer(
            colors: colors,
            offset: const Offset(0, 0),
            opacity: 0.72,
          ),
          Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              height: 94,
              width: 94,
              decoration: BoxDecoration(
                color: colors.coral,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Center(
                child: Container(height: 22, width: 22, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// _IsometricLayer renders one pale layer under the core mark.
class _IsometricLayer extends StatelessWidget {
  /// Creates a layer with a vertical offset and opacity.
  const _IsometricLayer({
    required this.colors,
    required this.offset,
    required this.opacity,
  });

  /// Active semantic color palette.
  final AgentAwesomePalette colors;

  /// Offset from the center.
  final Offset offset;

  /// Fill opacity.
  final double opacity;

  /// Builds the rotated layer.
  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: offset,
      child: Transform.rotate(
        angle: math.pi / 4,
        child: Container(
          width: 132,
          height: 132,
          decoration: BoxDecoration(
            color: colors.layerFill.withValues(alpha: opacity),
            border: Border.all(
              color: colors.layerBorder.withValues(alpha: 0.50),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

/// _OrbitPainter draws the dotted orbit and node points.
class _OrbitPainter extends CustomPainter {
  /// Creates the orbit painter with the active theme colors.
  const _OrbitPainter({required this.colors});

  /// Active semantic color palette.
  final AgentAwesomePalette colors;

  /// Paints the orbital guide behind the system diagram.
  @override
  void paint(Canvas canvas, Size size) {
    final orbitPaint = Paint()
      ..color = colors.orbit
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.88,
      height: size.height * 0.94,
    );
    const segments = 72;
    final sweep = (math.pi * 2) / segments;
    for (var index = 0; index < segments; index += 2) {
      canvas.drawArc(rect, index * sweep, sweep * 0.75, false, orbitPaint);
    }

    final nodePaint = Paint()
      ..color = colors.surface
      ..style = PaintingStyle.fill;
    final nodeBorder = Paint()
      ..color = colors.layerBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final angle in <double>[math.pi * 0.93, math.pi * 1.72]) {
      final point = Offset(
        rect.center.dx + math.cos(angle) * rect.width / 2,
        rect.center.dy + math.sin(angle) * rect.height / 2,
      );
      canvas.drawCircle(point, 6, nodePaint);
      canvas.drawCircle(point, 6, nodeBorder);
    }
  }

  /// Reports when the painter needs to redraw.
  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) {
    return colors != oldDelegate.colors;
  }
}
