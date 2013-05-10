# NAME

Template::PerlPP - Preprocessor that uses Perl syntax

# SYNOPSIS

    use Template::PerlPP;
    my $pp = Template::PerlPP->new;
    my $sub = $pp->parse_files($tenplate_name, $subtemplate_name);
    # or
    $sub = $pp->parse_strings($template, $subtemplate);
    my $output = $sub->($hash);

# DESCRIPTION

Template::PerlPP implements a text macro preprocessor. The preprocessor was
developed for creating html files, but is gqeneral purpose and can be used for
other tasks.

The macro preprocessor compiles a template to a subroutine. When you call the
subroutine with a reference to a hash or list, it fills the template with
corresponding fields from the data and produces a string.

# METHODS

There are three methds

    $obj = Template::PerlPP->new(command_start => '#', list_name => 'data');

Create a new parser. The configuration allows you to set the string which starts
a command (command_start) and the name used in the template if you pass the
subroutine a list instead of a hash (list_name).

    $sub = $obj->parse_strings($template, $subtemplate);

Generate a subroutine used to render data from a template and otionally a
subtemplate. It can be invoked by an object created by a call to new, or you
can Invoke it using the package name (Template::PerlPP), in which case it will
call new for you.

    $sub = $obj->parse_files($template_file, $subtemplate_file);

Like parse_strings, only the templates are read from the file names passed as
its arguments.

# TEMPLATE SYNTAX

If the first non-white char on a line is the coomand start sting, by default a
sharp character (C<#>). the line is interpreted as a command. The command name
must immediately follow the sharp character and continues up to the first white
space character. The text following the initial span of whitespace is the
command argument. The argument continues up to the end of the line.

Macros are ordinary Perl variables, starting with a dollar sign.

    $SUMMARY

is an examplea of a macro. A macro dictionary contains values that are
substituted for the macro names. This dictionary is an argument to the
preprocessor call. Values can also be added to the dictionary through
the #set command. If a macro is not found in the dictionary, the
interpolator dies.


## section

If a template contains a section, the text until the endsection command will
be replaced by the section with the same name in the subtemplate. For example,
if the main template has the code

    #section footer
    <div></div>
    #endsection 

and the subtemplate has the lines

    #section footer
    <div>This template is copyright with a Creative Commons License.</div>
    #endsection

The text will be copied from a section in the subtemplate into a section of the
same name in the template.

## set

Add a new value to the macro dictionary. The argument following the
command name looks like any Perl assignment statement minus the
trailing semicolon. Thw expression may contain 

    #set $URL = '<a href=\"http://www.stsci.edu/">Space Telescope</a>'

## do

The remainder of the line is interpreted as perl code. For assignments, use
the set command.

## if

The text until the matching C<#endif> is included only if the
expression in the C<#if> command is true.If false, the text is
skipped. The C<#if> command can contain an C<#else>, in which case the
text before the C<#else> is included if the expression in the C<#if>
command is true and the text after the C<#else> is included if it is
false. You can also place an C<#elsif> command in the C<#if> block,
which includes the following text if its expression is true.

    #if $HIGHLIGHT eq 'y'
    <em>$TEXT</em>
    #else
    $TEXT
    #endif

## while

Expand the text between the C<#while> and C<#endwhile> as long as the
expression following the C<#while> is true.

    #set $i = 10
    <p>Countdown ...<br>
    #while $i >= 0
    $i<br>
    #set $i = $i - 1
    #endwhile

## for

Expand the text between the C<#for> and <#endfor> commands several
times. The for command takes a name in the macro dictionary as its
argument. The value of this name should be a reference to a list. It
will expand the text in the for block once for each element in the
list.  Within the for block, any element of the list is treated as if
it were part of the macro dictionary. This is especially useful for
displaying lists of hashes. For example, suppose the macro dictionary
name PHONELIST points to an array. This array is a list of hashes, and
each hash has two entries, NAME and PHONE. Then the code

    #for @PHONELIST
    <p>$NAME<br>
    $PHONE</p>
    #endfor	

displays the entire phone list.

## with

Push the specified argument onto the dictionary stack. The argument
should be a hash reference. Inside the with block hash values can be
accessed by name.

    #with $PARAM
    <ul>
    <li>Name: $NAME</li>
    <li>Address: $ADDRESS</li>
    </ul>
    #endwith


# LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Bernie Simon <bernie.simon@gmail.com>
