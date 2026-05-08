module darkcommand;

public import darkcommand.command    : Command, Program,
                                       DarkCommandException,
                                       DarkCommandExitException,
                                       TopicGroup,
                                       addFlag, addOption, addArgument;
public import darkcommand.entry      : EntrySpec, EntryBuilder,
                                       isNullable, NullableTarget,
                                       isRepeatingField;
public import darkcommand.validators : IValidator, EnumValidator,
                                       DelegateValidator,
                                       FileSystemValidator;
public import darkcommand.utils      : levenshtein, suggest;
public import darkcommand.help            : printHelp, noColor;
public import darkcommand.completion.bash : generateBashCompletion;
public import darkcommand.docs.markdown   : generateMarkdownDocs;
