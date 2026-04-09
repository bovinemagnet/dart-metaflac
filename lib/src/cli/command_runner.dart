import 'package:args/command_runner.dart';

import 'commands/blocks_command.dart';
import 'commands/inspect_command.dart';
import 'commands/padding_command.dart';
import 'commands/picture_command.dart';
import 'commands/tags_command.dart';

/// Command runner for the metaflac CLI subcommand interface.
class MetaflacCommandRunner extends CommandRunner<int> {
  MetaflacCommandRunner()
      : super('metaflac', 'FLAC metadata editor') {
    addCommand(InspectCommand());
    addCommand(BlocksCommand());
    addCommand(TagsCommand());
    addCommand(PictureCommand());
    addCommand(PaddingCommand());
  }
}
