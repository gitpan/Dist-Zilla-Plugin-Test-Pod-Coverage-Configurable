package Dist::Zilla::Plugin::Test::Pod::Coverage::Configurable;
# git description: v0.01-4-gfc650a6

$Dist::Zilla::Plugin::Test::Pod::Coverage::Configurable::VERSION = '0.02';
use strict;
use warnings;
use namespace::autoclean;

use Data::Dumper ();
use Sub::Exporter::ForMethods;
use Data::Section 0.200002    # encoding and bytes
    { installer => Sub::Exporter::ForMethods::method_installer },
    '-setup' => { encoding => 'bytes' };
use Dist::Zilla::File::InMemory;

use Moose;

has class => (
    is      => 'ro',
    isa     => 'Str',
    default => 'Pod::Coverage::TrustPod',
);

has skip => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub { [] },
);

has trustme => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub { [] },
);

with qw(
    Dist::Zilla::Role::FileGatherer
    Dist::Zilla::Role::PrereqSource
);

sub mvp_multivalue_args {
    return qw( skip trustme );
}

# Register the release test prereq as a "develop requires"
# so it will be listed in "dzil listdeps --author"
sub register_prereqs {
    my ($self) = @_;

    $self->zilla->register_prereqs(
        {
            type  => 'requires',
            phase => 'develop',
        },
        'Test::Pod::Coverage'     => '1.08',
        'Test::More'              => '0.88',
        'Pod::Coverage::TrustPod' => 0,
    );
}

sub gather_files {
    my ($self) = @_;

    my $content = $self->_file_content();

    $self->add_file(
        Dist::Zilla::File::InMemory->new(
            {
                name    => 'xt/release/pod-coverage.t',
                content => $content,
            }
        ),
    );

    return;
}

my $head = <<'EOF';
#!perl
# This file was automatically generated by Dist::Zilla::Plugin::Test::Pod::Coverage::Configurable.

use Test::Pod::Coverage 1.08;
use Test::More 0.88;

BEGIN {
    if ( $] <= 5.008008 ) {
        plan skip_all => 'These tests require Pod::Coverage::TrustPod, which only works with Perl 5.8.9+';
    }
}
use Pod::Coverage::TrustPod;
EOF

sub _file_content {
    my $self = shift;

    my $content = $head;

    my $class = $self->class();
    if ( $class ne 'Pod::Coverage::TrustPod' ) {
        $content .= <<"EOF";

{
    package
        My::Coverage;
    use parent '$class', 'Pod::Coverage::TrustPod';
    \$INC{'My/Coverage.pm'} = 1;
}
EOF

        $class = 'My::Coverage';
    }

    my @skip_simple;
    my @skip_re;

    for my $skip ( @{ $self->skip() } ) {
        if ( $skip =~ /^qr/ ) {
            push @skip_re, $skip;
        }
        else {
            push @skip_simple, $skip;
        }
    }

    $content
        .= "\n"
        . 'my %skip = map { $_ => 1 } qw( '
        . ( join q{ }, @skip_simple ) . " );\n";

    $content .= <<'EOF';

my @modules;
for my $module ( all_modules() ) {
    next if $skip{$module};
EOF

    for my $skip_re (@skip_re) {
        $content .= "    next if \$module =~ $skip_re;\n";
    }

    $content .= <<'EOF';

    push @modules, $module;
}

plan skip_all => 'All the modules we found were excluded from POD coverage test.'
    unless @modules;

plan tests => scalar @modules;
EOF

    my %trustme;
    for my $pair ( @{ $self->trustme() } ) {
        my ( $module, $regex ) = split /\s*=>\s*/, $pair;

        my $qr;

        {
            local $@;
            $qr = eval $regex;
            if ($@) {
                die "Invalid regex in trustme for $module: $regex\n  $@\n";
            }
        };

        push @{ $trustme{$module} }, $qr;
    }

    if ( keys %trustme ) {
        my $trustme_dump = Data::Dumper->new( [ \%trustme ], ['*trustme'] )->Dump;
        $content .= "\nmy $trustme_dump";
    }
    else {
        $content .= "\nmy %trustme = ();\n";
    }

    $content .= <<"EOF";

for my \$module ( sort \@modules ) {
    pod_coverage_ok(
        \$module,
        {
            coverage_class => '$class',
            trustme        => \$trustme{\$module} || [],
        },
        "pod coverage for \$module"
    );
}

done_testing();
EOF

    return $content;
}

__PACKAGE__->meta->make_immutable;

1;

# ABSTRACT: dzil pod coverage tests with configurable parameters

__END__

=pod

=head1 NAME

Dist::Zilla::Plugin::Test::Pod::Coverage::Configurable - dzil pod coverage tests with configurable parameters

=head1 VERSION

version 0.02

=head1 SYNOPSIS

  [Test::Pod::Coverage::Configurable]
  class = Pod::Coverage::Moose
  trustme = Dist::Some::Module => qr/^(?:foo|bar)$/
  trustme = Dist::Some::Module => qr/^foo_/
  trustme = Dist::This::Module => qr/^bar_/
  skip = Dist::Other::Module
  skip = Dist::YA::Module
  skip = qr/^Dist::Foo/

=head1 DESCRIPTION

This is a L<Dist::Zilla> plugin that creates a POD coverage test for your
distro. Unlike the plugin that ships with dzil in core, this one is quite
configurable. The coverage test is generated as F<xt/release/pod-coverage.t>.

L<Test::Pod::Coverage> C<1.08>, L<Test::More> C<0.88>, and
L<Pod::Coverage::TrustPod> will be added as C<develop requires> dependencies.

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Test::Pod::Coverage::Configurable - a configurable release test for Pod coverage

=head1 CONFIGURATION

This plugin accepts the following configuration options

=head2 class

By default, this plugin uses L<Pod::Coverage::TrustPod> to run its tests. You
can provide an alternate class, such as L<Pod::Coverage::Moose>. If you
provide a class then the generate test file will create a subclass of the
class you provide and L<Pod::Coverage::TrustPod>.

This test can be configured by providing C<trustme>, C<skip>, and C<class>
parameters in your F<dist.ini> file.

Since this test always uses L<Pod::Coverage::TrustPod>, you can use that to
indicate that some subs should be treated as covered, even if no documentation
can be found, you can add:

  =for Pod::Coverage sub_name other_sub this_one_too

=head2 skip

This can either be a plain module name or a regex of the form C<qr/.../>. Any
modules defined here will be skipped entirely when testing POD coverage.

=head2 trustme

This parameter allows you to specify regexes for methods that should be
considered coverage on a per-module basis. The parameter is provided in the
form C<< Module::Name => qr/^regex/ >>. You can include the same module name
multiple times.

=head1 AUTHOR

Dave Rolsky <autarch@urth.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2014 by Dave Rolsky.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=cut
