#!/usr/bin/perl

use utf8;
use v5.14;
use strict;
use warnings;
use open ':std', ':encoding(utf8)';
use feature 'unicode_strings';

use Data::Dumper;
use List::Util qw< any none sample shuffle >;
use Path::Class;
use Term::ANSIColor;
use Text::Levenshtein qw(distance);
use Text::Wrap;
use WWW::Google::Translate;
use XML::Twig;

$| = 1;

my $wgt = WWW::Google::Translate->new({
    key => $ENV{GOOGLE_TRANSLATE_API_KEY},
});

##################################################################################################
# Globals

$Text::Wrap::columns = 1000;

our $NUM_OF_LANGUAGE_STEPS = 5;

our  $INPUT_BASE_DIR = './input';
our $OUTPUT_BASE_DIR = './output';

our $DEBUG = 2;

our $FINAL_LANGUAGE = 'English';
our @PROCESS_LANGUAGES = qw< English Japanese German >;

our $LANG_DEST_DIR = 'EnglishPoorlyTranslated';

# List borrowed from https://github.com/Systemcluster/d3translate/blob/master/d3translate/data.py
our %LANG_LIST = (
    'af'    => 'Afrikaans',
    'sq'    => 'Albanian',
    'am'    => 'Amharic',
    'ar'    => 'Arabic',
    'hy'    => 'Armenian',
    'az'    => 'Azerbaijani',
    'eu'    => 'Basque',
    'be'    => 'Belarusian',
    'bn'    => 'Bengali',
    'bs'    => 'Bosnian',
    'bg'    => 'Bulgarian',
    'ca'    => 'Catalan',
    'ceb'   => 'Cebuano',
    'ny'    => 'Chichewa',
    'zh'    => 'Chinese (Simplified)',
    'zh-TW' => 'Chinese (Traditional)',
    'co'    => 'Corsican',
    'hr'    => 'Croatian',
    'cs'    => 'Czech',
    'da'    => 'Danish',
    'nl'    => 'Dutch',
    'en'    => 'English',
    'eo'    => 'Esperanto',
    'et'    => 'Estonian',
    'tl'    => 'Filipino',
    'fi'    => 'Finnish',
    'fr'    => 'French',
    'fy'    => 'Frisian',
    'gl'    => 'Galician',
    'ka'    => 'Georgian',
    'de'    => 'German',
    'el'    => 'Greek',
    'gu'    => 'Gujarati',
    'ht'    => 'Haitian Creole',
    'ha'    => 'Hausa',
    'haw'   => 'Hawaiian',
    'iw'    => 'Hebrew',
    'hi'    => 'Hindi',
    'hmn'   => 'Hmong',
    'hu'    => 'Hungarian',
    'is'    => 'Icelandic',
    'ig'    => 'Igbo',
    'id'    => 'Indonesian',
    'ga'    => 'Irish',
    'it'    => 'Italian',
    'ja'    => 'Japanese',
    'jw'    => 'Javanese',
    'kn'    => 'Kannada',
    'kk'    => 'Kazakh',
    'km'    => 'Khmer',
    'ko'    => 'Korean',
    'ku'    => 'Kurdish (Kurmanji)',
    'ky'    => 'Kyrgyz',
    'lo'    => 'Lao',
    'la'    => 'Latin',
    'lv'    => 'Latvian',
    'lt'    => 'Lithuanian',
    'lb'    => 'Luxembourgish',
    'mk'    => 'Macedonian',
    'mg'    => 'Malagasy',
    'ms'    => 'Malay',
    'ml'    => 'Malayalam',
    'mt'    => 'Maltese',
    'mi'    => 'Maori',
    'mr'    => 'Marathi',
    'mn'    => 'Mongolian',
    'my'    => 'Myanmar (Burmese)',
    'ne'    => 'Nepali',
    'no'    => 'Norwegian',
    'ps'    => 'Pashto',
    'fa'    => 'Persian',
    'pl'    => 'Polish',
    'pt'    => 'Portuguese',
    'pa'    => 'Punjabi',
    'ro'    => 'Romanian',
    'ru'    => 'Russian',
    'sm'    => 'Samoan',
    'gd'    => 'Scots Gaelic',
    'sr'    => 'Serbian',
    'st'    => 'Sesotho',
    'sn'    => 'Shona',
    'sd'    => 'Sindhi',
    'si'    => 'Sinhala',
    'sk'    => 'Slovak',
    'sl'    => 'Slovenian',
    'so'    => 'Somali',
    'es'    => 'Spanish',
    'su'    => 'Sundanese',
    'sw'    => 'Swahili',
    'sv'    => 'Swedish',
    'tg'    => 'Tajik',
    'ta'    => 'Tamil',
    'te'    => 'Telugu',
    'th'    => 'Thai',
    'tr'    => 'Turkish',
    'uk'    => 'Ukrainian',
    'ur'    => 'Urdu',
    'uz'    => 'Uzbek',
    'vi'    => 'Vietnamese',
    'cy'    => 'Welsh',
    'xh'    => 'Xhosa',
    'yi'    => 'Yiddish',
    'yo'    => 'Yoruba',
    'zu'    => 'Zulu',
);

our %LANG2CODE;
$LANG2CODE{ $LANG_LIST{$_} } = $_ for keys %LANG_LIST;

# Also put in CamelCase names (which get used in RimWorld directories)
foreach my $lang_name (keys %LANG2CODE) {
    my $lang_code = $LANG2CODE{$lang_name};
    $lang_name =~ s/\W+//g;
    $LANG2CODE{$lang_name} = $lang_code;
}

# Google doesn't separate these
$LANG2CODE{PortugueseBrazilian} = 'pt';
$LANG2CODE{SpanishLatin}        = 'es';

our @LANG_BLACKLIST = (
    'eo',  # Esperanto
    'si',  # Sinhala    (swallows words)
    'id',  # Indonesian (swallows words)
    'mi',  # Maori      (swallows words)
    'nl',  # Dutch
    'fr',  # French
);

our @FILE_BLACKLIST = ( qw<
    About.txt
    FriendlyName.txt
    LanguageInfo.xml
    LangIcon.png
    README.md
>,  qr< Strings/WordParts/.+ >x,
);

our @UNIQUE_SUB_TEXT = (qw<
    Rumpelstiltskin
    Zyzzxxxxxzxzxzxzxxzxzxzxyxxz
    Qqqqqqqqqqqqqqqqqqqqqqqqqqqq
    Llanfairpwllgwyngyllgogery
    Chwyrndrobwllllantysiliogogogoch
    Chargoggagoggman
    Chaubunagungamaugg
    Taumatawhakatangi
    Hangakoauauotamatea
    Turipukakapikimaunga
    Horonukupokaiwhen
    Purangkuntjunya
    Keelafsnysleegte
    Venkatanarasim
    Harajuvaripeta
    Pekwachnamaykosk
    Waskwaypinwanik
    Ateritsiputeritsi
    Azpilicuetagaray
>);

##################################################################################################

# Look for files to process
foreach my $lang (@PROCESS_LANGUAGES) {
    my $lang_dir = dir($INPUT_BASE_DIR, 'Languages', $lang);
    process_dir($lang_dir, $lang, $lang_dir);
}

##################################################################################################
# Functions

# Because Path::Class::Dir->recurse does not sort...
sub process_dir {
    my ($lang_dir, $lang, $input_dir) = @_;
    foreach my $file_dir (sort $input_dir->children) {
        process_file($lang_dir, $lang, $file_dir) if !$file_dir->is_dir;
        process_dir ($lang_dir, $lang, $file_dir) if  $file_dir->is_dir;
    }
}

sub process_file {
    my ($lang_dir, $lang, $input_file) = @_;
    return if $input_file->is_dir;  # actually a directory

    # Parse filename
    my $basename = $input_file->basename;
    return unless $basename =~ /\.(xml|txt)$/i;
    my $ext = lc $1;

    my $relative_path = $input_file->relative($lang_dir);
    my $output_file   = file($OUTPUT_BASE_DIR, 'Languages', $LANG_DEST_DIR, $relative_path);

    # The output file should never ever be called "*Defs/*".  It's all singular.
    $output_file =~ s/Defs\b/Def/g;
    $output_file = file($output_file);

    # Auto-generate directories
    $output_file->dir->mkpath(1, 0755);

    # Blacklist check
    return if any {
        my $chk = $_;
        ref $chk eq 'Regexp' ? $relative_path =~ $chk : $relative_path eq $chk;
    } @FILE_BLACKLIST;

    # Never overwrite files
    return if -e $output_file;

    say "Parsing file: $input_file" if $DEBUG >= 1;

    my $lang_code = $LANG2CODE{$lang};

    if ($ext eq 'xml') {
        my $xml = XML::Twig->new(
            pretty_print => 'indented_c',
            comments     => 'keep',
        );
        $xml->parsefile($input_file->stringify);
        my $root = $xml->root;

        if ($root->name =~ /LanguageData|BackstoryTranslations/ && $root->has_children) {
            foreach my $child_node (grep { $_->is_pcdata } $root->descendants) {
                my $text     = $child_node->text;
                my $new_text;

                #warn "NODE: $text\nTYPE: ".$child_node->name."\nPARENT TYPE: ".$child_node->parent->name."\nGRANDPARENT TYPE: ".$child_node->parent->parent->name."\n";

                # RulesFiles aren't actually language strings.  They are prefix key to filename mappings.
                next if $child_node->parent->name eq 'li' && $child_node->parent->parent->name =~ /rulesFiles/;

                # Some of these are separated by \n or punctuation.  Process each sentence separately.
                while ($text =~ /
                    # Something with punctuation, spaces, and lookahead for a start of a new sentence
                    ([^\\]+?[.!?]+)( \s+ | (?=\p{Other_Letter}) )(?=\p{Uppercase}|\p{Titlecase}|\p{Other_Letter}) |
                    # Something with newlines
                    (.+?)( (?:\\n)+ ) |
                    # Everthing up to the last char
                    (.+)\z
                /gx) {
                    my $sentence = $1 // $3 // $5;
                    my $suffix   = $2 // $4 // '';
                    my $prefix   = '';

                    # The rules packs will have a prefix in the form of "SomeName(p=6)->".  These
                    # can't be translated because they are exact keys.
                    $prefix = $1 if $sentence =~ s/^([\w(=).\,!]+->)//;

                    # Eastern script might not follow proper punctuation spacing
                    $suffix = ' ' if !length $suffix && $sentence =~ /[.,!?:;]$/;

                    $new_text .= $prefix;
                    $new_text .= poorly_translate_text($lang_code, $sentence);
                    $new_text .= $suffix;
                }

                $child_node->set_text($new_text);
            }
        }

        say "Writing XML file: $output_file" if $DEBUG >= 1;

        my $out = $output_file->open('>:encoding(UTF-8)') || die "Can't open $output_file for writing: $!";
        $xml->print($out);
        $out->close;
        $xml->purge;
    }
    elsif ($ext eq 'txt') {
        my $in  = $input_file ->open('<:encoding(UTF-8)') || die "Can't open $input_file for reading: $!";
        my $out = $output_file->open('>:encoding(UTF-8)') || die "Can't open $output_file for writing: $!";

        while (defined( my $line = $in->getline )) {
            $line =~ s/\r//g;             # strip newline and re-print it later
            if ($line =~ s/^\N{BOM}//) {  # somebody set us up the BOM
                $out->print("\N{BOM}");
            }

            if ($line =~ m!^\s*//\s*|^\s*$!) {
                # skip comments or blank lines
                $out->say($line);
                next;
            }

            $line =~ s/^\s+|\s+$//g;

            # Since we can put an unlimited amount of text here, and have random results,
            # might as well insert twice the data
            my $previous_text = '';
            for (1, 2) {
                my $new_text = poorly_translate_text($lang_code, $line);

                if (lc $new_text eq lc $previous_text) {
                    say "Second run the same as the first; trying harder..." if $DEBUG >= 2;
                    local $NUM_OF_LANGUAGE_STEPS = $NUM_OF_LANGUAGE_STEPS * 2;
                    $new_text = poorly_translate_text($lang_code, $line);
                }

                $out->say($new_text) unless lc $new_text eq lc $previous_text;
                $previous_text = $new_text;
            }
        }

        say "Writing TXT file: $output_file" if $DEBUG >= 1;

        $out->close;
        $in->close;
    }
    else {
        die "Unknown extension: $ext";
    }

    say "\n";
}

sub poorly_translate_text {
    my ($starting_lang_code, $orig_text) = @_;

    # Don't dive too deeply into retry cycles
    die "Translation death spiral for: $orig_text" if (caller(15))[0];

    state $punct_end_re   = qr/[.,!?:;]$/;
    state $punct_split_re = qr/[\s().,!?:;\-]/;
    state $var_re         = qr/(?:
        [\p{Lowercase}']* (?: \{|\[ ) \w+ (?: \}|\] ) [\p{Lowercase}']* |
        \w+_\w+
    )/xa;  # use ASCII-only for \w, since variable names are bound to that

    # Short-circuit obvious non-words
    return $orig_text if length $orig_text <= 3 && $starting_lang_code eq $LANG2CODE{$FINAL_LANGUAGE};
    return $orig_text if $orig_text =~ /^( $var_re $punct_split_re* )+$/x;
    return $orig_text if $orig_text !~ /\p{Letter}|\p{Cased_Letter}|\p{Modifier_Letter}|\p{Other_Letter}/;

    # Try to retain capitalization
    my $letter_only_text = $orig_text;
    $letter_only_text =~ s/[^\pL]+//g;

    my $cap_type = 'mixed';
    $cap_type = 'upper'   if $letter_only_text =~ /^\p{Uppercase}+$/;
    $cap_type = 'lower'   if $letter_only_text =~ /^\p{Lowercase}+$/;
    $cap_type = 'ucfirst' if (
        $letter_only_text =~ /\p{Lowercase}/ && (
            $letter_only_text =~ /^(?:\p{Uppercase}|\p{Titlecase})/ ||   # Starts with a upper/title case
            ($orig_text =~ /^$var_re/ && $orig_text =~ $punct_end_re)    # OR starts with a variable and appears to be a sentence
        )
    );

    # Pick our other languages
    my @languages =
        grep {
            my $lang = $_;
            $lang ne $starting_lang_code && $lang ne $LANG2CODE{$FINAL_LANGUAGE} && none { $lang eq $_ } @LANG_BLACKLIST
        }
        sample $NUM_OF_LANGUAGE_STEPS * 2,
        keys %LANG_LIST
    ;
    @languages = @languages[0 .. $NUM_OF_LANGUAGE_STEPS-1];
    push @languages, $LANG2CODE{$FINAL_LANGUAGE};

    my $previous_lang_code = $starting_lang_code;
    my $text = $orig_text;

    # Before we begin, all of the variable substitutions need to be replaced with name-like words
    # that are much less likely to be mangled.
    my %substitutes;
    my @uniques = shuffle @UNIQUE_SUB_TEXT;
    while ($text =~ /($var_re)/gx) {
        my $vartext = $1;
        my $subtext = pop @uniques;
        die "Not enough unique subtitution words for this text block: $orig_text" unless $subtext;

        $substitutes{$subtext} = $vartext;
        $text =~ s/\Q$vartext\E/$subtext/g;

        # Make sure there's proper spacing in-between
        $text =~ s/(.+?)(?<!\s)$subtext/$1 $subtext/g;  # (.+?) = cheap way to get a ^ lookbehind
        $text =~ s/$subtext\K(?!\s|$)/ /g;
    }

    # Do the translate
    for (my $i = 0; $i <= $#languages; $i++) {
        my $lang_code = $languages[$i];
        if ($previous_lang_code eq $lang_code) {
            say "\tSkipping duplicate translation of ".$LANG_LIST{$lang_code}."..." if $DEBUG >= 2;
            next;
        }

        say "\tTranslating '$text' from ".$LANG_LIST{$previous_lang_code}." to ".$LANG_LIST{$lang_code}."..." if $DEBUG >= 3;

        # Le translate
        my %translate_options = (
            q           => $text,
            ( $previous_lang_code ? (source => $previous_lang_code) : () ),
            target      => $lang_code,
            format      => 'text',
            model       => 'base',
            prettyprint => 1,
        );
        $text = send_to_translate_api(%translate_options);

        unless (defined $text && length $text) {
            warn "STARTING CHARS: ".join(' ', map { ord(substr($orig_text, $_, 1)) } (0..8));

            warn "Trying again...\n";
            return poorly_translate_text($starting_lang_code, $orig_text);
        }

        # English ain't got no fancy Unicode letters (or fancy quoted words)
        if ($lang_code eq 'en') {
            my $unicode_only = $text;
            $unicode_only =~ s/\p{ASCII}+//g;

            if ($unicode_only =~ /\p{Letter}|\p{Cased_Letter}|\p{Modifier_Letter}|\p{Other_Letter}/ || $text =~ /\w{2,}'\w{3,}|\w+'\w+'\w+/) {
                if ($previous_lang_code) {
                    # Try one more time to translate with auto-detect turned on
                    say "\tText doesn't appear to be English, trying another translate: $text" if $DEBUG >= 2;
                    $previous_lang_code = '';
                    push @languages, 'en';
                    next;
                }
                else {
                    say "\tText STILL doesn't appear to be English, redoing the whole thing: $text" if $DEBUG >= 2;
                    return poorly_translate_text($starting_lang_code, $orig_text);
                }
            }
        }

        $previous_lang_code = $lang_code;
    }

    # Fix any punctuation problems
    if    ($orig_text =~ /\.$/ && $text !~ $punct_end_re) {
        $text .= '.';
    }
    elsif ($orig_text =~ /-$/  && $text !~ /-$/) {
        $text .= '-';
    }
    elsif ($orig_text =~ /\!$/ && $text !~ /\!$/) {
        $text =~ s/$punct_end_re//;
        $text .= '!';
    }
    elsif ($orig_text =~ /\?$/ && $text !~ /\?$/) {
        $text =~ s/$punct_end_re//;
        $text .= '?';
    }
    elsif ($orig_text !~ $punct_end_re && $text =~ $punct_end_re) {
        $text =~ s/$punct_end_re//;
    }

    $text =~ s/^[.,!?:;]// if $orig_text !~ /^[.,!?:;]/;

    # Rework back into the proper case
    $text = ucfirst lc $text if $cap_type eq 'ucfirst';
    $text =         uc $text if $cap_type eq 'upper';
    $text =         lc $text if $cap_type eq 'lower';

    $text =~ s/rimworld/RimWorld/gi;

    # Plug back in any subtitutions
    foreach my $subtext (sort keys %substitutes) {
        my $vartext = $substitutes{$subtext};

        $text =~ s/$subtext/$vartext/gi;

        # Look for inexact matches, based on LED
        unless ($text =~ /\Q$vartext\E/) {
            foreach my $word (sort { length $b <=> length $a } split /$punct_split_re+/, $text) {
                if (distance($subtext, $word) / length $subtext <= 0.33) {  # replace less than 33% of its length
                    $text =~ s/\Q$word\E/$vartext/gi;
                    last;
                }
            }
        }

        delete $substitutes{$subtext} if $text =~ /\Q$vartext\E/;  # keep track of failures
    }

    # Try harder to get a different result (within reason)
    if (lc $orig_text eq lc $text && $NUM_OF_LANGUAGE_STEPS < 50 && length $text > $NUM_OF_LANGUAGE_STEPS) {
        say "Result the same; trying harder..." if $DEBUG >= 2;
        local $NUM_OF_LANGUAGE_STEPS = $NUM_OF_LANGUAGE_STEPS * 2;
        return poorly_translate_text($starting_lang_code, $orig_text);
    }
    elsif (keys %substitutes) {
        say "Result missed some variables; trying again..." if $DEBUG >= 2;
        return poorly_translate_text($starting_lang_code, $orig_text);
    }

    warn colored(['bold yellow'],
        "Got a result that swallowed up a variable:\n".
        "$orig_text ==> $text\n".
        "Missing vars: ".join(' | ', map { "$_ => ".$substitutes{$_} } sort { $substitutes{$a} cmp $substitutes{$b} } keys %substitutes)
    )."\n" if keys %substitutes;

    warn colored(['bold yellow'],
        "Possible stray substition word:\n".
        "$orig_text ==> $text\n"
    )."\n" if $text =~ /(\A|\s)[\w\']{15,}(\s|\z)/;

    say "Final result: $orig_text ==> $text" if $DEBUG >= 2;
    return $text;
}

sub send_to_translate_api {
    my %translate_options = @_;

    my $res = eval { $wgt->translate(\%translate_options) };
    if ($@) {
        warn $@;
        sleep 2;
        my $res = $wgt->translate(\%translate_options);
    }

    my $text = $res->{data}{translations}[0]{translatedText};

    # Sometimes the 'base' model doesn't have a translation, but we favor it because it should
    # have a worse translation than new fancy machine learning models.
    if (defined $text && $text eq '' && $translate_options{model} ne 'nmt') {
        return send_to_translate_api(%translate_options, model => 'nmt');
    }

    unless (defined $text && length $text) {
        warn "No text from Google Translate API while processing: ".$translate_options{q}." ==> $text: ".Dumper($res);
    }

    return $text;
}
