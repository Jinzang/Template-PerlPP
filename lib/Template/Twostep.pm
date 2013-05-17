package Template::Twostep;

use 5.008005;
use strict;
use warnings;
use integer;

use IO::File;

our $VERSION = "0.76";

#----------------------------------------------------------------------
# Create a new template engine

sub new {
    my ($pkg, %config) = @_;

    my $parameters = $pkg->parameters();
    my %self = (%$parameters, %config);

    $self{command_start_pattern} = '^\s*' . quotemeta($self{command_start});
    $self{command_end_pattern} = quotemeta($self{command_end}) . '\s*$';

    return bless(\%self, $pkg);
}

#----------------------------------------------------------------------
# Compile a template into a subroutine which when called fills itself

sub compile_code {
    my ($self, $lines) = @_;

    my $code = <<'EOQ';
sub {
my $hash = Template::Hashlist->new (@_);
my $text = '';
EOQ

    push(@$lines, "\n");
    $code .= $self->parse_code($lines);

    $code .= <<'EOQ';
chomp $text;
return $text;
}
EOQ

    my $sub = eval ($code);
    die $@ unless $sub;
    return $sub;
}

#----------------------------------------------------------------------
# Compile a list of template files

sub compile_files {
    my ($pkg, @templates) = @_;
    my $self = ref $pkg ? $pkg : $pkg->new();

    # Template precedes subtemplate, which precedes subsubtemplate

    my @block;
    my $sections = {};
    while (my $filename = pop(@templates)) {
        my $fd = IO::File->new($filename, 'r');
        die "Couldn't read $filename: $!\n" unless $fd;

        my @lines = <$fd>;
        close $fd;

        @block = $self->parse_block($sections, \@lines, '');
    }

    return $self->compile_code(\@block);
}

#----------------------------------------------------------------------
# Compile a list of templates contained in strings

sub compile_strings {
    my ($pkg, @templates) = @_;
    my $self = ref $pkg ? $pkg : $pkg->new();

    # Template precedes subtemplate, which precedes subsubtemplate

    my @block;
    my $sections = {};
    foreach my $template (reverse @templates) {
        my @lines = map {"$_\n"} split(/\n/, $template);
        @block = $self->parse_block($sections, \@lines, '');
    }

    return $self->compile_code(\@block);
}

#----------------------------------------------------------------------
# Replace variable references with hashlist fetches

sub encode {
    my ($self, $value) = @_;

    if (defined $value) {
        my $pre = '{$hash->fetch(\'';
        my $post = '\')}';
        $value =~ s/(?<!\\)([\$\@\%])(\w+)/$1$pre$2$post/g;

    } else {
        $value = '';
    }

    return $value;
}

#----------------------------------------------------------------------
# Get the translation of a template command

sub get_command {
    my ($self, $cmd) = @_;

    my $commands = {
                    do => "%%;",
                    for => "foreach (%%) {\n\$hash->push(\$_);",
                	endfor => "\$hash->pop();\n}",
                    if => "if (%%) {",
                    elsif => "} elsif (%%) {",
                    else => "} else {",
                    endif => "}",
                    set => \&set,
                    while => "while (%%) {",
                    endwhile => "}",
                	with => "\$hash->push(\\%%);",
                    endwith => "\$hash->pop();",
                    };

    return $commands->{$cmd};
}

#----------------------------------------------------------------------
# Is a command a singleton command?

sub is_singleton {
    my ($self, $cmd) = @_;

    return ! ($cmd eq 'section' || $self->get_command("end$cmd"));
}

#----------------------------------------------------------------------
# Set default parameters for package

sub parameters {
    my ($pkg) = @_;

    my $parameters = {
                      command_start => '#',
                      command_end => '',
                      };

    return $parameters;
}

#----------------------------------------------------------------------
# Read and check the template files

sub parse_block {
    my ($self, $sections, $lines, $command) = @_;

    my @block;
    while (defined (my $line = shift @$lines)) {
        my ($cmd, $arg) = $self->parse_command($line);

        if (defined $cmd) {
            if (substr($cmd, 0, 3) eq 'end') {
                $arg = substr($cmd, 3);
                die "Mismatched block end ($command/$arg)"
                    if defined $arg && $arg ne $command;

                push(@block, $line);
                return @block;

            } elsif ($self->is_singleton($cmd)) {
                push(@block, $line);

            } else {
                my @sub_block = $self->parse_block($sections, $lines, $cmd);

                if ($cmd eq 'section') {
                    pop(@sub_block);
                    $sections->{$arg} = \@sub_block unless exists $sections->{$arg};
                    push(@block, @{$sections->{$arg}});

                } else {
                    push(@block, $line, @sub_block);
                }
            }

        } else {
            push(@block, $line);
        }
    }

    die "Missing end" if $command;
    return @block;
}

#----------------------------------------------------------------------
# Parse the templace source

sub parse_code {
    my ($self, $lines) = @_;

    my $code = '';
    my $stash = '';

    while (defined (my $line = shift @$lines)) {
        my ($cmd, $arg) = $self->parse_command($line);

        if (defined $cmd) {
            if (length $stash) {
                $code .= "\$text .= <<\"EOQ\";\n";
                $code .= "${stash}EOQ\n";
                $stash = '';
            }

            my $command = $self->get_command($cmd);
            die "Unknown command: $cmd\n" unless defined $command;

            my $ref = ref ($command);
            if (! $ref) {
                $arg = $self->encode($arg);
                $command =~ s/%%/$arg/;
                $code .= "$command\n";

            } elsif ($ref eq 'CODE') {
                $code .= $command->($self, $arg);

            } else {
                die "I don't know how to handle a $ref: $cmd";
            }

        } else {
            $stash .= $self->encode($line);
        }
    }

    if (length $stash) {
        $code .= "\$text .= <<\"EOQ\";\n";
        $code .= "${stash}EOQ\n";
    }

    return $code;
}

#----------------------------------------------------------------------
# Parse a command and its argument

sub parse_command {
    my ($self, $line) = @_;

    if ($line =~ s/$self->{command_start_pattern}//) {
        $line =~ s/$self->{command_end_pattern}//;
        $line =~ s/\s+$//;

        return split(' ', $line, 2)
    }

    return;
}

#----------------------------------------------------------------------
# Generate code for the set command, which stores results in the hashlist

sub set {
    my ($self, $arg) = @_;

    my ($var, $expr) = split (/\s*=\s*/, $arg, 2);
    $expr = $self->encode ($expr);

    return "\$hash->store(\'$var\', ($expr));\n";
}

#----------------------------------------------------------------------
# The hashlist stores variables passed to the fill routine

package Template::Hashlist;

sub new {
    my ($pkg, @hash) = @_;

    my $self = bless ([], $pkg);
    foreach my $hash (@hash) {
        $hash = {data => $hash} unless ref $hash eq 'HASH';
        $self->push ($hash);
    }

    return $self;
}

#----------------------------------------------------------------------
# Find and retrieve a value from the hash list

sub fetch {
    my ($self, $name) = @_;

    for my $hash (@$self) {
        return $hash->{$name} if exists $hash->{$name};
    }

    die "Variable $name is undefined";
}

#----------------------------------------------------------------------
# Remove hashes pushed on the list by the for command

sub pop {
    my ($self) = @_;
    return shift (@$self);
}

#----------------------------------------------------------------------
# Push a hash on the list of hashes, used in for loops

sub push {
    my ($self, $hash) = @_;
    return unless defined $hash;

    my $newhash = {};
    my $ref = ref ($hash);
    if (! $ref) {
        $newhash->{data} = \$hash;

    } elsif ($ref ne 'HASH') {
        $newhash->{data} = $hash;

    } else {
        while (my ($name, $entry) = each %$hash) {
            if (ref $entry) {
                $newhash->{$name} = $entry;
            } else {
                $newhash->{$name} = \$entry;
            }
        }
    }

    unshift (@$self, $newhash);
}

#----------------------------------------------------------------------
# Store a variable in the hashlist, used by set

sub store {
    my ($self, $var, @val) = @_;

    my ($sigil, $name) = $var =~ /([\$\@\%])(\w+)/;
    die "Unrecognized variable type: $name" unless defined $sigil;

    my $i;
    for ($i = 0; $i < @$self; $i ++) {
        last if exists $self->[$i]{$name};
    }

    $i = 0 unless $i < @$self;

    if ($sigil eq '$') {
        my $val = @val == 1 ? $val[0] : @val;
        $self->[$i]{$name} = \$val;

    } elsif ($sigil eq '@') {
        $self->[$i]{$name} = \@val;

    } elsif ($sigil eq '%') {
        my %val = @val;
        $self->[$i]{$name} = \%val;
    }

    return;
}

1;

=pod

=encoding utf-8

=head1 NAME

Template::Twostep - Compile templates into a subroutine

=head1 SYNOPSIS

    use Template::Twostep;
    my $tt = Template::Twostep->new;
    my $sub = $tt->compile_files($tenplate_name, $subtemplate_name);
    # or
    $sub = $tt->compile_strings($template, $subtemplate);
    my $output = $sub->($hash);

=head1 DESCRIPTION

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
configurable, but is a sharp character (C<#>) by default. The command start
string may be preceded by whitespace. If a command is a block command, it is
terminated by the word "end" followed by the command name. For example, the for
command is terminated by an endfor command and the if command by an endif
command.

All lines may contain variables. As in Perl, variables are a sigil character
(C<$>, C<@>, or C<&>) followed by one or more word characters. For example,
C<$name> or C<@names>. To indicate a literal character instead of a variable,
precede the sigil with a backslash. When you run the subroutine that this module
generetaes, you pass it a reference to some data, which is usually a hash. The
subroutine replaces variables with the value in the field of the same name in
the hash. The sigil on the variable should match the type of data contained in
the hash field: a C<$> if it is a scalar, a C<@> if it is an array reference, or
a C<%> if it is a hash reference. If the two disagree, you will get a run time
error. You can pass a reference to an array instead of a hash to the subroutine
this module generates. If you do, the template will use C<@data> to refer to the
array passed to the subroutine.

=head1 METHODS

This three module has three public methods. The first, new, changes the module
defaults. Compile_files and compile_strings generate a subroutine from one or more
templates. You then call this subroutine with a reference to the data you want
to substitute into the template to produce output.

Using subtemplates along with a template allows you to place the common design
elements in the template. You indicate where to replace parts of the template
with parts of the template with the section command. If the template contains a
section command with the same name as one of the subtemplates, it replaces the
contents of the template inside the section with the contents of the
corresponding block in the subtemplate.

=over 4

=item $obj = Template::Twostep->new(command_start => '#', command_end => '');

Create a new parser. The configuration allows you to set the string which starts
a command (command_start) and the string which ends a command (command_end).
All commands end at the end of line. However, you may widh to place commends
inside comments and comments may require a closing string. By setting
command_end, the closing string will be stripped from the end of the string.

=item $sub = $obj->compile_strings($template, $subtemplate);

Generate a subroutine used to render data from a template and optionally one or
more subtemplates. It can be invoked by an object created by a call to new, or
you can invoke it using the package name (Template::Twostep), in which case it
will first call new for you.

=item $sub = $obj->compile_files($template_file, $subtemplate_file);

Like compile_strings, only the templates are read from the file names passed as
its arguments.

=back

=head1 TEMPLATE SYNTAX

If the first non-white char on a line is the coomand start string, by default a
sharp character (C<#>). the line is interpreted as a command. The command name
continues up to the first white space character. The text following the initial
span of whitespace is the command argument. The argument continues up to the end
of the line.

Variables in the template have the same format as ordinary Perl variables,
a string of word characters starting with a sigil character. for example,

    $SUMMARY @data %dictionary

is an examplea of a macro. The subroutine this module generates will substitute
values in the data it is passed for the variables. New variables  can be added
with the C<set> command. If a corresponing is not found in the data, the
interpolator dies with the error undefined variable name.

=over 4

=item do

The remainder of the line is interpreted as perl code. For assignments, use
the set command.

=item if

The text until the matching C<endif> is included only if the expression in the
C<if> command is true.If false, the text is skipped. The C<if> command can
contain an C<else>, in which case the text before the C<else> is included if
the expression in the C<if> command is true and the text after the C<else> is
included if it is false. You can also place an C<elsif> command in the C<if>
block, which includes the following text if its expression is true.

    #if $highlight eq 'y'
    <em>$text</em>
    #else
    $text
    #endif

=item for

Expand the text between the C<for> and <endfor> commands several times. The
for command takes a name of a field in a hash as its argument. The value of this
name should be a reference to a list. It will expand the text in the for block
once for each element in the list. Within the for block, any element of the list
is accesible. This is especially useful for displaying lists of hashes. For
example, suppose the data field name PHONELIST points to an array. This array is
a list of hashes, and each hash has two entries, NAME and PHONE. Then the code

    #for @PHONELIST
    <p>$NAME<br>
    $PHONE</p>
    #endfor

displays the entire phone list.

=item section

If a template contains a section, the text until the endsection command will be
replaced by the section block with the same name one the subtemplates. For
example, if the main template has the code

    #section footer
    <div></div>
    #endsection

and the subtemplate has the lines

    #section footer
    <div>This template is copyright with a Creative Commons License.</div>
    #endsection

The text will be copied from a section in the subtemplate into a section of the
same name in the template. If there is no block with the same name, the text is
not changed.

=item set

Adds a new variable or updates the value of an existing variable. The argument
following the command name looks like any Perl assignment statement minus the
trailing semicolon. For example,

    #set $link = "<a href=\"$url\">$title</a>"

=item while

Expand the text between the C<while> and C<endwhile> as long as the
expression following the C<while> is true.

    #set $i = 10
    <p>Countdown ...<br>
    #while $i >= 0
    $i<br>
    #set $i = $i - 1
    #endwhile

=item with

Lists with a hash can be accessed using the for command. Hashes within a hash
are accessed using the with command. For example:

    #with %address
    <p><i>$street<br />
    $city, $state $zip</i></p.
    #endwith

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
