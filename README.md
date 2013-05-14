## NAME

Template::Twostep - Compile templates into a subroutine

## SYNOPSIS

    use Template::Twostep;
    my $pp = Template::Twostep->new;
    my $sub = $pp->compile_files($tenplate_name, $subtemplate_name);
    # or
    $sub = $pp->compile_strings($template, $subtemplate);
    my $output = $sub->($hash);

# DESCRIPTION

This module simplifies the job of producing repetetive text output by letting
you put data into a template. Templates also support the control structures in
Perl: for and while loops, if else blocks, and some others. Creating output
is a two step process. First you generate a subroutine from one or more
templates, then you call the subroutine with your data to generate the output.
This approach has the advantage of speeding things up when the same template
is used more than once. However, it also poses a security risk because code
you might not want executed may be included in the template. For this reason
if the script using this module can be run from the web, make sure the account
that runs it cannot write to the template. There are many template handling
modules and you might wonder why there needs to be another. My reason for
writing it is that it provides better control over whitespace than other
template modules, which can be important for some data formats.

The template format is line oriented. Commands occupy a single line and
continue to the end of line. Commands start with a string, which is
configurable, but is a sharp character (#) by default. The command start
string may be preceded by whitespace. If a command is block oriented, it is
terminated by the word "end" followed by the command name. For example, the for
command is terminated by an endfor command and the if command by an endif
command.

All lines may contain variables. As in Perl, variables are a sigil character
($, @, or &) followed by one or more word characters. For example,
$name or @names. To indicate a literal character instead of a variable,
precede the sigil with a backslash. When you run the subroutine that this module
generetaes, you pass it a reference to some data, which is usually a hash. The
subroutine replaces variables with the value in the field of the same name in
the hash. The sigil on the variable should match the type of data contained in
the hash field: a $ if it is a scalar, a @ if it is an array reference, or
a % if it is a hash reference. If the two disagree, you will get a run time
error. You can pass a reference to an array instead of a hash to the subroutine
this module generates. If you do, the template will refer to it using variable
the string contained in list_name. By dedaule this is data, so templates will
use @data to refer to the array passed to the subroutine.

For further explanation of the methods and syntax, please read the pod
documentation ath the end of the source file.

## LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

## AUTHOR

Bernie Simon <bernie.simon@gmail.com>
