/// Provides reusable workspace, task-plan, and chat timeline widgets.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../domain/models.dart';
import '../panels/panels.dart';
import '../shell/app_sections.dart';

/// HomeWorkspace renders the default Today workspace surface.
class HomeWorkspace extends StatelessWidget {
  /// Creates the Today workspace bound to app state.
  const HomeWorkspace({
    super.key,
    required this.controller,
    this.onOpenSection,
  });

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  /// Opens a top-level workspace from hero and path actions.
  final ValueChanged<String>? onOpenSection;

  /// Builds the Today assistant workspace.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _HeroPanel(onOpenSection: onOpenSection),
          const SizedBox(height: 28),
          Text(
            'Choose your path',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 20),
          _PathGrid(onOpenSection: onOpenSection),
          const SizedBox(height: 34),
          Text(
            'Live Workspace',
            style: TextStyle(
              color: colors.ink,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            controller.statusMessage,
            style: TextStyle(color: colors.muted, fontSize: 17),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final hasTasks = controller.executionSteps.isNotEmpty;
              final chatColumn = controller.messages.isEmpty
                  ? const PanelEmptyBlock(label: 'No live chat messages')
                  : Column(
                      children: <Widget>[
                        for (final message in controller.messages)
                          ChatRow(message: message),
                      ],
                    );
              if (!hasTasks) {
                return chatColumn;
              }
              if (constraints.maxWidth < 760) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ExecutionPlan(tasks: controller.executionSteps),
                    const SizedBox(height: 32),
                    chatColumn,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 300,
                    child: ExecutionPlan(tasks: controller.executionSteps),
                  ),
                  const SizedBox(width: 36),
                  Expanded(child: chatColumn),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// _HeroPanel renders the screenshot-inspired welcome surface.
class _HeroPanel extends StatelessWidget {
  /// Creates the home hero panel.
  const _HeroPanel({required this.onOpenSection});

  /// Opens app sections from hero calls to action.
  final ValueChanged<String>? onOpenSection;

  /// Builds the bordered hero with copy and system diagram.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      constraints: const BoxConstraints(minHeight: 430),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.shadow,
            blurRadius: 38,
            offset: Offset(0, 20),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[colors.surface, colors.heroEnd],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          final copy = _HeroCopy(compact: !wide, onOpenSection: onOpenSection);
          final diagram = _AgentSystemDiagram(compact: !wide);
          if (!wide) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  copy,
                  const SizedBox(height: 28),
                  SizedBox(height: 320, child: diagram),
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(74, 58, 52, 48),
            child: Row(
              children: <Widget>[
                Expanded(flex: 7, child: copy),
                const SizedBox(width: 36),
                Expanded(flex: 6, child: diagram),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// _HeroCopy renders the primary welcome headline and actions.
class _HeroCopy extends StatelessWidget {
  /// Creates the hero copy block.
  const _HeroCopy({required this.compact, required this.onOpenSection});

  /// Whether to use a smaller type scale.
  final bool compact;

  /// Opens app sections from hero actions.
  final ValueChanged<String>? onOpenSection;

  /// Builds the hero text and buttons.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _WorkspaceEyebrow('AGENT AWESOME AI', color: colors.coral),
        const SizedBox(height: 22),
        Text(
          'Design and\nrun your AI\nagent system',
          style: Theme.of(
            context,
          ).textTheme.displayLarge?.copyWith(fontSize: compact ? 48 : 72),
        ),
        const SizedBox(height: 26),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 610),
          child: Text(
            'Agent Awesome gives you everything you need to build, run, and ship reliable AI agents with the models, tools, memory, workflows, and deployment paths you control.',
            style: TextStyle(
              color: colors.muted,
              fontSize: 24,
              height: 1.5,
              letterSpacing: 0,
            ),
          ),
        ),
        const SizedBox(height: 34),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: <Widget>[
            _HeroActionButton(
              label: 'Start Building',
              primary: true,
              compact: compact,
              onPressed: onOpenSection == null
                  ? null
                  : () => onOpenSection!(AppSections.chat),
            ),
            _HeroActionButton(
              label: 'Open Backlog',
              primary: false,
              compact: compact,
              onPressed: onOpenSection == null
                  ? null
                  : () => onOpenSection!(AppSections.backlog),
            ),
          ],
        ),
      ],
    );
  }
}

/// _HeroActionButton renders one hero call to action.
class _HeroActionButton extends StatelessWidget {
  /// Creates a hero action button.
  const _HeroActionButton({
    required this.label,
    required this.primary,
    required this.compact,
    required this.onPressed,
  });

  /// Visible button label.
  final String label;

  /// Whether the button uses the coral treatment.
  final bool primary;

  /// Whether the button needs compact padding and text treatment.
  final bool compact;

  /// Action callback.
  final VoidCallback? onPressed;

  /// Builds the hero action.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final style = primary
        ? FilledButton.styleFrom(
            backgroundColor: colors.coral,
            foregroundColor: Colors.white,
            disabledBackgroundColor: colors.coral,
            disabledForegroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 16 : 24,
              vertical: compact ? 14 : 18,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: colors.ink,
            disabledForegroundColor: colors.ink,
            side: BorderSide(color: colors.border),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 16 : 24,
              vertical: compact ? 14 : 18,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          );
    final child = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 230 : 320),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 16 : 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          if (!compact) ...const <Widget>[
            SizedBox(width: 14),
            Icon(Icons.arrow_forward, size: 18),
          ],
        ],
      ),
    );
    return primary
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}

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
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colors.shadow,
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
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
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: colors.shadow,
                    blurRadius: 30,
                    offset: Offset(0, 18),
                  ),
                ],
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

/// _PathGrid renders the path cards under the hero.
class _PathGrid extends StatelessWidget {
  /// Creates the path grid.
  const _PathGrid({required this.onOpenSection});

  /// Opens a workspace section from a path card.
  final ValueChanged<String>? onOpenSection;

  /// Builds responsive path cards.
  @override
  Widget build(BuildContext context) {
    const paths = <_PathCardData>[
      _PathCardData(
        title: 'Daily Console',
        detail: 'Review status, live work, and assistant activity.',
        icon: Icons.dashboard_customize_outlined,
        section: AppSections.today,
      ),
      _PathCardData(
        title: 'Conversation Builder',
        detail: 'Start or continue a run with a configured profile.',
        icon: Icons.forum_outlined,
        section: AppSections.chat,
      ),
      _PathCardData(
        title: 'Task Stream',
        detail: 'Shape backlog work into queue, stream, and terrain views.',
        icon: Icons.task_alt_outlined,
        section: AppSections.backlog,
      ),
      _PathCardData(
        title: 'Memory Map',
        detail: 'Inspect context, entities, timelines, and remembered facts.',
        icon: Icons.hub_outlined,
        section: AppSections.memory,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 4
            : constraints.maxWidth >= 700
            ? 2
            : 1;
        final spacing = 20.0;
        final cardWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final path in paths)
              SizedBox(
                width: cardWidth,
                child: _PathCard(
                  data: path,
                  onTap: onOpenSection == null
                      ? null
                      : () => onOpenSection!(path.section),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// _PathCardData stores one home path card.
class _PathCardData {
  /// Creates path-card content.
  const _PathCardData({
    required this.title,
    required this.detail,
    required this.icon,
    required this.section,
  });

  /// Card title.
  final String title;

  /// Card supporting text.
  final String detail;

  /// Card icon.
  final IconData icon;

  /// Section opened from the card.
  final String section;
}

/// _PathCard renders one selectable home path.
class _PathCard extends StatelessWidget {
  /// Creates a path card.
  const _PathCard({required this.data, required this.onTap});

  /// Card content.
  final _PathCardData data;

  /// Selection callback.
  final VoidCallback? onTap;

  /// Builds one path card.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 158),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: colors.cardIconBackground,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(data.icon, color: colors.cardIcon, size: 24),
            ),
            const SizedBox(height: 18),
            Text(
              data.title,
              style: TextStyle(
                color: colors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              data.detail,
              style: TextStyle(
                color: colors.muted,
                height: 1.45,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ExecutionPlan renders active workspace tasks as an objective list.
class ExecutionPlan extends StatelessWidget {
  /// Creates a task plan.
  const ExecutionPlan({super.key, required this.tasks});

  /// Plan task rows.
  final List<WorkspaceTask> tasks;

  /// Builds the active objective task plan.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.circle, size: 10, color: colors.green),
            const SizedBox(width: 12),
            _WorkspaceEyebrow('EXECUTION PLAN', color: colors.green),
          ],
        ),
        const SizedBox(height: 24),
        for (final task in tasks)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: TaskLine(task: task),
          ),
      ],
    );
  }
}

/// TaskLine renders one workspace task row.
class TaskLine extends StatelessWidget {
  /// Creates one plan or task row.
  const TaskLine({super.key, required this.task, this.onComplete});

  /// Task data to display.
  final WorkspaceTask task;

  /// Optional completion callback.
  final VoidCallback? onComplete;

  /// Builds one plan or task row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final mark = task.done
        ? Icon(Icons.check, size: 16, color: colors.green)
        : task.active
        ? Icon(Icons.circle, size: 13, color: colors.green)
        : const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onComplete,
          child: Container(
            height: 30,
            width: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: task.done ? colors.greenSoft : Colors.transparent,
              border: Border.all(
                color: task.done || task.active ? colors.green : colors.border,
              ),
            ),
            child: Center(child: mark),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                task.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(task.detail, style: TextStyle(color: colors.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

/// ChatRow renders one chat timeline entry.
class ChatRow extends StatelessWidget {
  /// Creates one chat timeline row.
  const ChatRow({super.key, required this.message});

  /// Message to display.
  final ChatMessage message;

  /// Builds one chat timeline row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    if (message.role == ChatRole.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 20),
          constraints: const BoxConstraints(maxWidth: 640),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.panel,
            borderRadius: BorderRadius.circular(36),
          ),
          child: _MessageText(message: message),
        ),
      );
    }
    if (message.role == ChatRole.tool) {
      return Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.extension_outlined, color: colors.green),
            const SizedBox(width: 12),
            Expanded(child: _MessageText(message: message)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 25,
            backgroundColor: colors.green,
            child: Icon(Icons.auto_awesome, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(child: _MessageText(message: message)),
        ],
      ),
    );
  }
}

class _WorkspaceEyebrow extends StatelessWidget {
  const _WorkspaceEyebrow(this.text, {this.color});

  final String text;
  final Color? color;

  /// Builds a small uppercase label.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Text(
      text,
      style: TextStyle(
        color: color ?? colors.green,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 4,
      ),
    );
  }
}

class _MessageText extends StatelessWidget {
  const _MessageText({required this.message});

  final ChatMessage message;

  /// Builds message author and text.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final time =
        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: message.author,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: colors.ink,
                            ),
                          ),
                          TextSpan(
                            text: '  $time',
                            style: TextStyle(color: colors.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _CopyMessageButton(text: message.text),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SelectableText(
          message.text,
          style: TextStyle(color: colors.ink, fontSize: 16, height: 1.55),
        ),
      ],
    );
  }
}

class _CopyMessageButton extends StatelessWidget {
  const _CopyMessageButton({required this.text});

  final String text;

  /// Builds a compact control for copying one chat message.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Tooltip(
      message: 'Copy message',
      child: IconButton(
        onPressed: () {
          unawaited(Clipboard.setData(ClipboardData(text: text)));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Copied'),
              duration: Duration(milliseconds: 900),
            ),
          );
        },
        icon: const Icon(Icons.copy_outlined),
        color: colors.muted,
        iconSize: 15,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        visualDensity: VisualDensity.compact,
        splashRadius: 16,
      ),
    );
  }
}
