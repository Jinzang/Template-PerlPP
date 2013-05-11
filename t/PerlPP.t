#!/usr/bin/env perl
use strict;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Test::More tests => 18;

#----------------------------------------------------------------------
# Create object

BEGIN {use_ok("Template::PerlPP");} # test 1

my $pp = Template::PerlPP->new();
isa_ok($pp, "Template::PerlPP"); # test 2
can_ok($pp, qw(parse_files parse_strings)); # test 3

#----------------------------------------------------------------------
# Test parse_block

my $template = <<'EOQ';
#section header
Header
#endsection
#set $i = 0
#for @data
  #set $i = $i + 1
  #if $i % 2
Even line
  #else
Odd line
  #endif
#endfor
#section footer
Footer
#endsection
EOQ

my $sections = {};
my @lines = map {"$_\n"} split(/\n/, $template);
my @ok = grep {$_ !~ /section/} @lines;

my @block = $pp->parse_block($sections, \@lines, '');
my @sections = sort keys %$sections;

is_deeply(\@block, \@ok, "All lines returned from parse_block"); # test 4
is_deeply(\@sections, [qw(footer header)],
          "All sections returned from parse_block"); #test 5
is_deeply($sections->{footer}, ["Footer\n"],
          "Right value in footer from parse_block"); # test 6

my $subtemplate = <<'EOQ';
#section header
Another Header
#endsection
Another Body
#section footer
Another Footer
#endsection
EOQ

@lines = map {"$_\n"} split(/\n/, $template);
my @sublines = map {"$_\n"} split(/\n/, $subtemplate);
@ok = grep {$_ !~ /section/} @lines;
$ok[0] = "Another Header\n";
$ok[-1] = "Another Footer\n";

$sections = {};
@block = $pp->parse_block($sections, \@sublines, '');
@block = $pp->parse_block($sections, \@lines, '');

is_deeply(\@block, \@ok, "Template and subtemplate with parse_block"); # test 7
is_deeply($sections->{header}, ["Another Header\n"],
          "Right value in header for template & subtemplate");

my $sub = $pp->parse_strings($template, $subtemplate);
is(ref $sub, 'CODE', "Compiled template"); # test 9

my $text = $sub->([1, 2]);
my $text_ok = <<'EOQ';
Another Header
Even line
Odd line
Another Footer
EOQ

is($text, $text_ok, "Run compiled template"); # test 10

#----------------------------------------------------------------------
# Test configurable command start and end

$template = <<'EOQ';
/*set $x2 = 2 * $x */
2 * $x = $x2
EOQ

$pp = Template::PerlPP->new(command_start => '/*', command_end => '*/');
$sub = $pp->parse_strings($template);
$text = $sub->({x => 3});

is($text, "2 * 3 = 6\n", "Configurable start and end"); # test 11

#----------------------------------------------------------------------
# Test for loop

$template = <<'EOQ';
#for @list
$name $sep $phone
#endfor
EOQ

$sub = Template::PerlPP->parse_strings($template);
my $data = {sep => ':', list => [{name => 'Ann', phone => '4444'},
                                 {name => 'Joe', phone => '5555'}]};

$text = $sub->($data);

$text_ok = <<'EOQ';
Ann : 4444
Joe : 5555
EOQ

is($text, $text_ok, "For loop"); # test 12

#----------------------------------------------------------------------
# Test with block

$template = <<'EOQ';
$a
#with %hash
$a $b
#endwith
$b
EOQ

$sub = Template::PerlPP->parse_strings($template);
$data = {a=> 1, b => 2, hash => {a => 10, b => 20}};

$text = $sub->($data);

$text_ok = <<'EOQ';
1
10 20
2
EOQ

is($text, $text_ok, "With block"); # test 13

#----------------------------------------------------------------------
# Test while loop

$template = <<'EOQ';
#while $count
$count
#set $count = $count - 1
#endwhile
go
EOQ

$sub = Template::PerlPP->parse_strings($template);
$data = {count => 3};

$text = $sub->($data);

$text_ok = <<'EOQ';
3
2
1
go
EOQ

is($text, $text_ok, "While loop"); # test 14

#----------------------------------------------------------------------
# Test if blocks

$template = <<'EOQ';
#if $x == 1
\$x is $x (one)
#elsif $x  == 2
\$x is $x (two)
#else
\$x is unknown
#endif
EOQ

$sub = Template::PerlPP->parse_strings($template);

$data = {x => 1};
$text = $sub->($data);
is($text, "\$x is 1 (one)\n", "If block"); # test 15

$data = {x => 2};
$text = $sub->($data);
is($text, "\$x is 2 (two)\n", "Elsif block"); # test 16

$data = {x => 3};
$text = $sub->($data);
is($text, "\$x is unknown\n", "Elsif block"); # test 17

#----------------------------------------------------------------------
# Create test directory

system("/bin/rm -rf $Bin/../test");
mkdir "$Bin/../test";

$template = <<'EOQ';
#section header
Dummy Header
#endsection
#for @data
$name $phone
#endfor
#section footer
Dummy Footer
#endsection
EOQ

$subtemplate = <<'EOQ';
#section header
Phone List
----
#endsection

#section footer
----
#set $num = @data
$num people
#endsection
EOQ

my $template_file = "$Bin/../test/template.txt";
my $fd = IO::File->new($template_file, 'w');
print $fd $template;
close $fd;

my $subtemplate_file = "$Bin/../test/subtemplate.txt";
$fd = IO::File->new($subtemplate_file, 'w');
print $fd $subtemplate;
close $fd;

$sub = Template::PerlPP->parse_files($template_file, $subtemplate_file);

$data = [{name => 'Ann', phone => 4444},
         {name => 'Joe', phone => 5555}];

$text = $sub->($data);
$text_ok = <<'EOQ';
Phone List
----
Ann 4444
Joe 5555
----
2 people
EOQ

is($text, $text_ok, "Parse files"); # test 18
