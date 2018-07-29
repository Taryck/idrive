#*****************************************************************************************************
# To Convert perl list/hash to json string & vice versa
#
# Created By : Yogesh Kumar
# Reviewed By: Deepak Chaurasia
#****************************************************************************************************/

package JSON;

use 5.010001;
use strict;
use warnings;

use Scalar::Util qw(reftype looks_like_number);

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(from_json to_json);

sub _fail { die __PACKAGE__.": $_[0] at offset ".pos()."\n" }

my %escape_codes = (
	"\\" => "\\",
	"\"" => "\"",
	"b" => "\b",
	"f" => "\f",
	"n" => "\n",
	"r" => "\r",
	"t" => "\t",
);

sub _decode_str {
	my $str = shift;
		$str =~ s[(\\(?:([0-7]{1,3})|x([0-9A-Fa-f]{1,2})|(.)))]
							[defined($2) ? chr(oct $2) :
							defined($3) ? chr(hex $3) :
							$escape_codes{$4} ? $escape_codes{$4} :
							$1]eg;
	$str;
}

our $FROM_JSON = qr{

(?:
    (?&VALUE) (?{ $_ = $^R->[1] })
|
    \z (?{ _fail "Unexpected end of input" })
|
      (?{ _fail "Invalid literal" })
)

(?(DEFINE)

(?<OBJECT>
  \{\s*
    (?{ [$^R, {}] })
    (?:
        (?&KV) # [[$^R, {}], $k, $v]
        (?{ [$^R->[0][0], {$^R->[1] => $^R->[2]}] })
        \s*
        (?:
            (?:
                ,\s* (?&KV) # [[$^R, {...}], $k, $v]
                (?{ $^R->[0][1]{ $^R->[1] } = $^R->[2]; $^R->[0] })
            )*
        |
            (?:[^,\}]|\z) (?{ _fail "Expected ',' or '\x7d'" })
        )*
    )?
    \s*
    (?:
        \}
    |
        (?:.|\z) (?{ _fail "Expected closing of hash" })
    )
)

(?<KV>
  (?&STRING) # [$^R, "string"]
  \s*
  (?:
      :\s* (?&VALUE) # [[$^R, "string"], $value]
      (?{ [$^R->[0][0], $^R->[0][1], $^R->[1]] })
  |
      (?:[^:]|\z) (?{ _fail "Expected ':'" })
  )
)

(?<ARRAY>
  \[\s*
  (?{ [$^R, []] })
  (?:
      (?&VALUE) # [[$^R, []], $val]
      (?{ [$^R->[0][0], [$^R->[1]]] })
      \s*
      (?:
          (?:
              ,\s* (?&VALUE)
              (?{ push @{$^R->[0][1]}, $^R->[1]; $^R->[0] })
          )*
      |
          (?: [^,\]]|\z ) (?{ _fail "Expected ',' or '\x5d'" })
      )
  )?
  \s*
  (?:
      \]
  |
      (?:.|\z) (?{ _fail "Expected closing of array" })
  )
)

(?<VALUE>
  \s*
  (
      (?&STRING)
  |
      (?&NUMBER)
  |
      (?&OBJECT)
  |
      (?&ARRAY)
  |
      true (?{ [$^R, 1] })
  |
      false (?{ [$^R, 0] })
  |
      null (?{ [$^R, undef] })
  )
  \s*
)

(?<STRING>
    "
    (
        (?:
            [^\\"]+
        |
            \\ [0-7]{1,3}
        |
            \\ x [0-9A-Fa-f]{1,2}
        |
            \\ ["\\/bfnrt]
        #|
        #    \\ u [0-9a-fA-f]{4}
        |
            \\ (.) (?{ _fail "Invalid string escape character $^N" })
        )*
    )
    (?:
        "
    |
        (?:\\|\z) (?{ _fail "Expected closing of string" })
    )

  (?{ [$^R, _decode_str($^N)] })
)

(?<NUMBER>
  (
    -?
    (?: 0 | [1-9][0-9]* )
    (?: \. [0-9]+ )?
    (?: [eE] [-+]? [0-9]+ )?
  )

  (?{ [$^R, 0+$^N] })
)

) }xms;

sub from_json {
	state $re = qr{\A$FROM_JSON\z};
	local $_ = shift;
	local $^R;
	eval { $_ =~ $re } and return $_;
	die $@ if $@;
	die 'no match';
}

sub to_json {
	my ($ref) = @_;

	if(ref($ref) eq "HASH") {
			return "{".join(",",map { "\"$_\":".to_json($ref->{$_}) } sort keys %$ref)."}";
	}
	elsif(ref($ref) eq "ARRAY") {
			return "[".join(",",map { to_json($_) } @$ref)."]";
	}
	else {
			return "null" if ! defined $ref;
			return $ref   if (looks_like_number($ref) and int($ref) eq $ref);
			my %esc = (
					"\n" => '\n',
					"\r" => '\r',
					"\t" => '\t',
					"\f" => '\f',
					"\b" => '\b',
					"\"" => '\"',
					"\\" => '\\\\',
					"\'" => '\\\'',
			);
			$ref =~ s/([\x22\x5c\n\r\t\f\b])/$esc{$1}/g;
			$ref =~ s/([\x00-\x08\x0b\x0e-\x1f])/'\\u00' . unpack('H2', $1)/eg;
			return "\"$ref\"";
	}
}
1;
