/// Provides reusable workspace, task-plan, and chat timeline widgets.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../domain/models.dart';
import '../panels/panels.dart';

/// HomeWorkspace renders the default Today workspace surface.
class HomeWorkspace extends StatelessWidget {
  /// Creates the Today workspace bound to app state.
  const HomeWorkspace({super.key, required this.controller});

  /// Shared app controller.
  final AuroraAppController controller;

  /// Builds the Today assistant workspace.
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(36, 36, 36, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _WorkspaceEyebrow('TODAY', color: AuroraColors.coral),
          const SizedBox(height: 22),
          Text(
            'Live Workspace',
            style: Theme.of(context).textTheme.displayLarge,
          ),
          const SizedBox(height: 10),
          Text(
            controller.statusMessage,
            style: const TextStyle(color: AuroraColors.muted, fontSize: 17),
          ),
          const SizedBox(height: 38),
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

/// ExecutionPlan renders active workspace tasks as an objective list.
class ExecutionPlan extends StatelessWidget {
  /// Creates a task plan.
  const ExecutionPlan({super.key, required this.tasks});

  /// Plan task rows.
  final List<WorkspaceTask> tasks;

  /// Builds the active objective task plan.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Row(
          children: <Widget>[
            Icon(Icons.circle, size: 10, color: AuroraColors.green),
            SizedBox(width: 12),
            _WorkspaceEyebrow('EXECUTION PLAN'),
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
    final mark = task.done
        ? const Icon(Icons.check, size: 16, color: AuroraColors.green)
        : task.active
        ? const Icon(Icons.circle, size: 13, color: AuroraColors.green)
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
              color: task.done ? const Color(0xffeef5e9) : Colors.transparent,
              border: Border.all(
                color: task.done || task.active
                    ? AuroraColors.green
                    : AuroraColors.border,
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
              Text(
                task.detail,
                style: const TextStyle(color: AuroraColors.muted),
              ),
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
    if (message.role == ChatRole.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 20),
          constraints: const BoxConstraints(maxWidth: 640),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AuroraColors.panel,
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
          color: const Color(0xfffffcf8),
          border: Border.all(color: AuroraColors.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.extension_outlined, color: AuroraColors.green),
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
          const CircleAvatar(
            radius: 25,
            backgroundColor: AuroraColors.green,
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
  const _WorkspaceEyebrow(this.text, {this.color = AuroraColors.green});

  final String text;
  final Color color;

  /// Builds a small uppercase label.
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color,
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
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AuroraColors.ink,
                            ),
                          ),
                          TextSpan(
                            text: '  $time',
                            style: const TextStyle(color: AuroraColors.muted),
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
          style: const TextStyle(fontSize: 16, height: 1.55),
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
        color: AuroraColors.muted,
        iconSize: 15,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        visualDensity: VisualDensity.compact,
        splashRadius: 16,
      ),
    );
  }
}
