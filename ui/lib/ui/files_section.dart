/// Renders file-only management surfaces for source documents.
library;

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/theme.dart';
import '../domain/models.dart';
import 'panels/panels.dart';

part 'files_section_shell.dart';
part 'files_section_library.dart';
part 'files_section_inspector.dart';
part 'files_section_models.dart';
part 'files_section_helpers.dart';

const String _fileDetailsModeId = 'details';
const String _fileSourceModeId = 'source';
const String _fileAccessModeId = 'access';
