package Catmandu::Importer::LDAP;

use Catmandu::Sane;
use Catmandu::Util qw(:is);
use Moo;
use Net::LDAP;

with 'Catmandu::Importer';

has host          => (is => 'ro', default => sub { 'ldap://127.0.0.1:389' });
has base          => (is => 'ro', predicate => 1);
has password      => (is => 'ro', predicate => 1);
has search_base   => (is => 'ro', predicate => 1);
has search_filter => (is => 'ro', predicate => 1);
has ldap          => (is => 'ro', lazy => 1, builder => '_build_ldap');
has attributes    => (
    is     => 'ro',
    coerce => sub {
        my $attrs = $_[0];
        if (is_string $attrs) {
            return { map { $_ => {} } split ',', $attrs };
        }
        if (is_array_ref $attrs) {
            return { map { $_ => {} } @$attrs };
        }
        if ($attrs) {
            for my $attr (keys %$attrs) {
                $attrs->{$attr} = {} unless ref $attrs->{$attr};
            };
        }
        $attrs;
    },
);

sub _build_ldap {
    my $self = $_[0];
    my $ldap = Net::LDAP->new($self->host) || confess $@;
    my $bind = $self->has_base
        ? $self->has_password
            ? $ldap->bind($self->base, password => $self->password)
            : $ldap->bind($self->base)
        : $ldap->bind;
    $bind->code && confess $bind->error;
    $ldap;
}

sub _new_search {
    my $self = $_[0];
    my %args;
    $args{base}   = $self->search_base   if $self->has_search_base;
    $args{filter} = $self->search_filter if $self->has_search_filter;
    if (my $attrs = $self->attributes) {
        $args{attrs} = keys %$attrs;
    }
    my $search = $self->ldap->search(%args);
    $search->code && confess $search->error;
    $search;
}

sub generator {
    my $self = $_[0];
    sub {
        state $search = $self->_new_search;
        my $entry = $search->shift_entry // return;
        my $data = {};
        if (my $attrs = $self->attributes) {
            for my $attr (keys %$attrs) {
                my $config = $attrs->{$attr};
                my $val = $entry->get_value($attr, asref => $config->{array}) // next;
                $data->{$config->{as} // $attr} = $config->{array} ? [@$val] : $val;
            }
        } else {
            for my $attr ($entry->attributes) {
                my $val = $entry->get_value($attr, asref => 1);
                $data->{$attr} = [@$val];
            }
        }
        $data;
    };
}

=head1 NAME

Catmandu::Importer::LDAP - Package that imports LDAP directories

=head1 SYNOPSIS

    use Catmandu::Importer::LDAP;

    my $importer = Catmandu::Importer::LDAP->new(
        base => "...",
        password => "...",
        search_base => "...",
        search_filter => "(&(...)(...))",
        attributes => {
            name => 1,
            # or
            name => {as => "Name"},
            # or
            name => {as => "Name", array => 1},
        },
    );

    my $n = $importer->each(sub {
        my $hashref = $_[0];
        # ...
    });

=cut

1;
