use warnings;
use strict;

BEGIN {
  use Test::More;
  eval "use Types::Standard; 1;" || do {
    plan skip_all => "Trouble loading Types::Standard => $@";
  };

  package MyApp::Types;
  $INC{'MyApp/Types.pm'} = __FILE__;

  use strict;
  use warnings;
 
  use Type::Utils -all;
  use Types::Standard -types;
  use Type::Library
   -base,
   -declare => qw( UserId User ContextLike );

  extends "Types::Standard"; 

  class_type User, { class => "MyApp::Model::User::user" };
  duck_type ContextLike, [qw/model/];

  declare UserId,
   as Int,
   where { $_ < 5 };

  # Tests using this are skipped pending deeper thought
  coerce User,
   from ContextLike,
     via { $_->model('User')->find( $_->req->args->[0] ) };
}

{
  package MyApp::Model::User;
  $INC{'MyApp/Model/User.pm'} = __FILE__;

  use base 'Catalyst::Model';

  our %users = (
    1 => { name => 'john', age => 46 },
    2 => { name => 'mary', age => 36 },
    3 => { name => 'ian', age => 25 },
    4 => { name => 'visha', age => 18 },
  );

  sub find {
    my ($self, $id) = @_;
    my $user = $users{$id} || return;
    return bless $user, "MyApp::Model::User::user";
  }

  package MyApp::Controller::Root;
  $INC{'MyApp/Controller/Root.pm'} = __FILE__;

  use Moose;
  use MooseX::MethodAttributes;
  use MyApp::Types qw/Tuple Int Str StrMatch UserId User/;

  extends 'Catalyst::Controller';

  sub user :Local Args(UserId) {
    my ($self, $c, $int) = @_;
    my $user = $c->model("User")->find($int);
    $c->res->body("name: $user->{name}, age: $user->{age}");
  }

  # Tests using this are current skipped pending coercion rethink
  sub user_object :Local Args(User) Coerce(1) {
    my ($self, $c, $user) = @_;
    $c->res->body("name: $user->{name}, age: $user->{age}");
  }

  sub an_int :Local Args(Int) {
    my ($self, $c, $int) = @_;
    $c->res->body('an_int');
  }

  sub many_ints :Local Args(ArrayRef[Int]) {
    my ($self, $c, $int) = @_;
    $c->res->body('many_ints');
  }

  sub tuple :Local Args(Tuple[Str,Int]) {
    my ($self, $c, $str, $int) = @_;
    $c->res->body('tuple');
  }

  sub match :Local Args(StrMatch[qr{\d\d-\d\d-\d\d}]) {
    my ($self, $c, $int) = @_;
    $c->res->body('match');
  }

  sub any_priority :Path('priority_test') Args(1) { $_[1]->res->body('any_priority') }

  sub int_priority :Path('priority_test') Args(Int) { $_[1]->res->body('int_priority') }

  sub chain_base :Chained(/) CaptureArgs(1) { }

    sub any_priority_chain :Chained(chain_base) PathPart('') Args(1) { $_[1]->res->body('any_priority_chain') }

    sub int_priority_chain :Chained(chain_base) PathPart('') Args(Int) { $_[1]->res->body('int_priority_chain') }

    sub link_any :Chained(chain_base) PathPart('') CaptureArgs(1) { }

      sub any_priority_link_any :Chained(link_any) PathPart('') Args(1) { $_[1]->res->body('any_priority_link_any') }

      sub int_priority_link_any :Chained(link_any) PathPart('') Args(Int) { $_[1]->res->body('int_priority_link_any') }
    
    sub link_int :Chained(chain_base) PathPart('') CaptureArgs(Int) { }

      sub any_priority_link :Chained(link_int) PathPart('') Args(1) { $_[1]->res->body('any_priority_link') }

      sub int_priority_link :Chained(link_int) PathPart('') Args(Int) { $_[1]->res->body('int_priority_link') }


  sub default :Default {
    my ($self, $c, $int) = @_;
    $c->res->body('default');
  }

  MyApp::Controller::Root->config(namespace=>'');

  package MyApp;
  use Catalyst;

  MyApp->setup;
}

use Catalyst::Test 'MyApp';

{
  my $res = request '/an_int/1';
  is $res->content, 'an_int';
}

{
  my $res = request '/an_int/aa';
  is $res->content, 'default';
}

{
  my $res = request '/many_ints/1';
  is $res->content, 'many_ints';
}

{
  my $res = request '/many_ints/1/2';
  is $res->content, 'many_ints';
}

{
  my $res = request '/many_ints/1/2/3';
  is $res->content, 'many_ints';
}

{
  my $res = request '/many_ints/1/2/a';
  is $res->content, 'default';
}

{
  my $res = request '/priority_test/1';
  is $res->content, 'int_priority';
}

{
  my $res = request '/priority_test/a';
  is $res->content, 'any_priority';
}

{
  my $res = request '/tuple/aaa/111';
  is $res->content, 'tuple';
}

{
  my $res = request '/tuple/aaa/aaa';
  is $res->content, 'default';
}

{
  my $res = request '/match/11-22-33';
  is $res->content, 'match';
}

{
  my $res = request '/match/aaa';
  is $res->content, 'default';
}

{
  my $res = request '/user/2';
  is $res->content, 'name: mary, age: 36';
}

{
  my $res = request '/user/20';
  is $res->content, 'default';
}


SKIP: {
  skip "coercion support needs more thought", 1;
  my $res = request '/user_object/20';
  is $res->content, 'default';
}

SKIP: {
  skip "coercion support needs more thought", 1;
  my $res = request '/user_object/2';
  is $res->content, 'name: mary, age: 36';
}

{
  my $res = request '/chain_base/capture/arg';
  is $res->content, 'any_priority_chain';
}

{
  my $res = request '/chain_base/cap1/100/arg';
  is $res->content, 'any_priority_link';
}

{
  my $res = request '/chain_base/cap1/101/102';
  is $res->content, 'int_priority_link';
}

{
  my $res = request '/chain_base/capture/100';
  is $res->content, 'int_priority_chain', 'got expected';
}

{
  my $res = request '/chain_base/cap1/a/arg';
  is $res->content, 'any_priority_link_any';
}

{
  my $res = request '/chain_base/cap1/a/102';
  is $res->content, 'int_priority_link_any';
}

done_testing;