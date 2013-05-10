package Template::PerlPP;
use 5.008005;
use strict;
use warnings;

our $VERSION = "0.70";

use strict;
use warnings;
use IO::File;

use constant DEFAULTS => {
                          command_start => '#',
                          list_name => 'data',
                          };

use constant SINGLETON => {
                            do => 1,
                            else => 1,
                            elsif => 1,
                            set => 1,
                          };

use constant COMMANDS => {
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

#----------------------------------------------------------------------
# Create a new template engine

sub new {
    my ($pkg, %config) = @_;
    
    my $defaults = DEFAULTS;
    my %self = (%$defaults, %config);
    
    $self{command_pattern} = '^\s*' . quotemeta($self{command_start});
    return bless(\%self, $pkg);
}

#----------------------------------------------------------------------
# Compile a template into a subroutine which when called fills itself

sub compile {
    my ($self, $lines) = @_;

    my $code = <<"EOQ";
sub {
my \$hash = Template::Hashlist->new ('$self->{list_name}', \@_);
my \$text;
EOQ

    push(@$lines, "\n");
    $code .= $self->parse_code($lines);

    $code .= <<'EOQ';
chomp $text;
return $text;
}
EOQ
    return eval ($code);
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
# Read and check the template files

sub parse_block {
    my ($self, $sections, $lines, $command) = @_;

    my @block;
    my $singleton = SINGLETON;
    
    while (defined (my $line = shift @$lines)) {
        my ($cmd, $arg) = $self->parse_command($line);
        
        if (! defined $cmd) {
            push(@block, $line);

        } else {
            if (substr($cmd, 0, 3) eq 'end') {
                $arg = substr($cmd, 3);
                die "Mismatched block end ($command/$arg)"
                    if defined $arg && $arg ne $command;

                push(@block, $line);
                return @block;

            } elsif ($singleton->{$cmd}) {
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
    my $commands = COMMANDS;
    
    while (defined (my $line = shift @$lines)) {
        my ($cmd, $arg) = $self->parse_command($line);
        
        if (defined $cmd) {
            if (length $stash) {
                $code .= "\$text .= <<\"EOQ\";\n";
                $code .= "${stash}EOQ\n";
                $stash = '';
            }

            die "Unknown command: $cmd\n" unless exists $commands->{$cmd};
            
            my $command = $commands->{$cmd};
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
    
    if ($line =~ s/$self->{command_pattern}//) {
        $line =~ s/\s+$//;
        return split(' ', $line, 2)
    }
    
    return;
}

#----------------------------------------------------------------------
# Parse a list of template files

sub parse_files {
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
    
    return $self->compile(\@block);
}

#----------------------------------------------------------------------
# Parse a list of templates contained in strings

sub parse_strings {
    my ($pkg, @templates) = @_;
    my $self = ref $pkg ? $pkg : $pkg->new();
    
    # Template precedes subtemplate, which precedes subsubtemplate
    
    my @block;
    my $sections = {};
    foreach my $template (reverse @templates) {
        my @lines = map {"$_\n"} split(/\n/, $template);
        @block = $self->parse_block($sections, \@lines, '');
    }
    
    return $self->compile(\@block);
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
    my ($pkg, $list_name, @hash) = @_;
    
    my $self = bless ([], $pkg);
    foreach my $hash (@hash) {
        $hash = {$list_name => $hash} unless ref $hash eq 'HASH';
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
        $newhash->{self} = \$hash;

    } elsif ($ref ne 'HASH') {
        $newhash->{self} = $hash;

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

PerlPP - Preprocessor that uses Perl syntax

=head1 SYNOPSIS

    use Template::PerlPP;
    my $pp = Template::PerlPP->new;
    my $sub = $pp->parse_files($tenplate_name, $subtemplate_name);
    # or
    $sub = $pp->parse_strings($template, $subtemplate);
    my $output = $sub->($hash);

=head1 DESCRIPTION

Template::PerlPP implements a text macro preprocessor. The preprocessor was
developed for creating html files, but is gqeneral purpose and can be used for
other tasks.

The macro preprocessor compiles a template to a subroutine. When you call the
subroutine with a reference to a hash or list, it fills the template with
corresponding fields from the data and produces a string.

=head1 METHODS

There are three methds

=over 4

=item $obj = Template::PerlPP->new(command_start => '#', list_name => 'data');

Create a new parser. The configuration allows you to set the string which starts
a command (command_start) and the name used in the template if you pass the
subroutine a list instead of a hash (list_name).

=item $sub = $obj->parse_strings($template, $subtemplate);

Generate a subroutine used to render data from a template and otionally a
subtemplate. It can be invoked by an object created by a call to new, or you
can Invoke it using the package name (Template::PerlPP), in which case it will
call new for you.

=item $sub = $obj->parse_files($template_file, $subtemplate_file);

Like parse_strings, only the templates are read from the file names passed as
its arguments.

=back

=head1 TEMPLATE SYNTAX

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
the C<#set> command. If a macro is not found in the dictionary, the
interpolator dies.

=over 4

=item section

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

=item #set

Add a new value to the macro dictionary. The argument following the
command name looks like any Perl assignment statement minus the
trailing semicolon. Thw expression may contain 

    #set $URL = '<a href=\"http://www.stsci.edu/">Space Telescope</a>'

=item #do

The remainder of the line is interpreted as perl code. For assignments, use
the set command.

=item #if

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

=item #while

Expand the text between the C<#while> and C<#endwhile> as long as the
expression following the C<#while> is true.

    #set $i = 10
    <p>Countdown ...<br>
    #while $i >= 0
    $i<br>
    #set $i = $i - 1
    #endwhile

=item #for

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

=item with

Push the specified argument onto the dictionary stack. The argument
should be a hash reference. Inside the with block hash values can be
accessed by name.

    #with $PARAM
    <ul>
    <li>Name: $NAME</li>
    <li>Address: $ADDRESS</li>
    </ul>
    #endwith

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
