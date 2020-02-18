#!/usr/bin/perl

use utf8;
use v5.14;
use strict;
use warnings;
use open ':std', ':encoding(utf8)';
use feature 'unicode_strings';

use Data::Dumper;
use List::Util qw< any none >;
use Path::Class;
use Text::Wrap;
use XML::Twig;

use lib './lib';
use PoorlyTranslateUtils;

$| = 1;

##################################################################################################
# Globals

$Text::Wrap::columns = 1000;

our  $INPUT_BASE_DIR = './input';
our $OUTPUT_BASE_DIR = './output';

our $DEBUG = 2;

our @PROCESS_LANGUAGES = qw< English German Japanese >;

our $LANG_DEST_DIR = 'EnglishPoorlyTranslated';

our @FILE_BLACKLIST = ( qw<
    About.txt
    FriendlyName.txt
    LanguageInfo.xml
    LangIcon.png
    README.md
>,  qr< Strings/WordParts/.+ >x,
);

our %XML_TRANSLATION_KEYS;

##################################################################################################

# Read XML files for translation keys
{
    my $lang_dir = dir($OUTPUT_BASE_DIR, 'Languages', $LANG_DEST_DIR);
    process_dir($lang_dir, 'en', $lang_dir, 'process_file_for_xml_keys');
    say "\n" if $DEBUG >= 2;
}

# Look for files to process
foreach my $lang (@PROCESS_LANGUAGES) {
    my $lang_dir = dir($INPUT_BASE_DIR, 'Languages', $lang);
    process_dir($lang_dir, $lang, $lang_dir, 'process_file_for_translation');
}

##################################################################################################
# Functions

# Because Path::Class::Dir->recurse does not sort...
sub process_dir {
    my ($lang_dir, $lang, $input_dir, $func) = @_;
    foreach my $file_dir (sort $input_dir->children) {
        no strict 'refs';
        &$func     ($lang_dir, $lang, $file_dir)        if !$file_dir->is_dir;
        process_dir($lang_dir, $lang, $file_dir, $func) if  $file_dir->is_dir;
    }
}

sub process_file_for_xml_keys {
    my ($lang_dir, $lang, $output_file) = @_;
    return if $output_file->is_dir;  # actually a directory

    # Parse filename
    my $basename = $output_file->basename;
    return unless $basename =~ /\.xml$/i;

    say "Reading XML data from: $output_file" if $DEBUG >= 2;

    my $lang_code = $LANG2CODE{$lang};

    my $xml = XML::Twig->new(
        pretty_print => 'indented_c',
        comments     => 'keep',
    );
    $xml->parsefile($output_file->stringify);
    my $root = $xml->root;

    if ($root->name =~ /LanguageData|BackstoryTranslations/ && $root->has_children) {
        my $write_back = 0;

        foreach my $child_node (grep { $_->is_pcdata } $root->descendants) {
            my $text = $child_node->text;
            next unless defined $text && length $text;

            my $is_okay = _check_xml_node_key( check_then_delete => $child_node, $output_file );
            $write_back = 1 unless $is_okay;

            _check_xml_node_key( add => $child_node, $output_file );
        }

        if ($write_back) {
            # If we deleted down to nothing, delete this entire file
            if (!$root->has_children) {
                say "Removed all nodes; deleting $output_file!\n" if $DEBUG >= 1;
                $output_file->remove;
                return;
            }

            say "Re-writing XML file: $output_file" if $DEBUG >= 1;

            my $out = $output_file->open('>:encoding(UTF-8)') || die "Can't open $output_file for writing: $!";
            $xml->print($out);
            $out->close;
            $xml->purge;
        }
    }

    $xml->purge;
}

sub _check_xml_node_key {
    my ($cmd, $child_node, $file) = @_;
    return unless $child_node->twig;  # child node already deleted?

    my $root = $child_node->twig->root;
    my $parent_node = $child_node->parent;

    if ($root->name eq 'LanguageData') {
        # Part of a larger rules set
        if ($parent_node->name eq 'li') {
            $parent_node = $parent_node->parent;

            # These don't seem to be affected by even duplicated parent nodes
            return 1 if $parent_node->name =~ /\.rulePack\.rulesFiles$/;
        }
    }
    elsif ($root->name eq 'BackstoryTranslations') {
        # Only check the parent node once, so skip the other two child tags
        return 1 if $parent_node->name ne 'title';
        $parent_node = $parent_node->parent;
    }
    else {
        die "No clue how to parse XML from root ".$root->name;
    }

    # Some XML tags may be duplicated between different def-injected sections, so the base
    # directory name needs to be part of the key.
    my $base_dir = $file->dir;
    while ($base_dir->parent->basename ne 'Languages') { $base_dir = $base_dir->parent; }  # ie: end at Languages/<lang>
    my $relative_dir = $file->relative($base_dir)->dir;

    $relative_dir =~ s!Defs!Def!g;
    $relative_dir = dir($relative_dir);

    my $xml_key    = join('/', $relative_dir, $parent_node->name);
    my $dupe_check = $XML_TRANSLATION_KEYS{$xml_key};

    if    ($cmd eq 'add') {
        warn "\tFound duplicate key $xml_key!\n" if $dupe_check && $dupe_check ne $file;
        return $dupe_check ? 0 : ($XML_TRANSLATION_KEYS{$xml_key} = $file);
    }
    elsif ($cmd eq 'check_then_delete') {
        return $dupe_check && $dupe_check ne $file ? $parent_node->delete : 1
    }

    die "What's $cmd?";
}

sub process_file_for_translation {
    my ($lang_dir, $lang, $input_file) = @_;
    return if $input_file->is_dir;  # actually a directory

    # Parse filename
    my $basename = $input_file->basename;
    return unless $basename =~ /\.(xml|txt)$/i;
    my $ext = lc $1;

    my $relative_path = $input_file->relative($lang_dir);
    my $output_file   = file($OUTPUT_BASE_DIR, 'Languages', $LANG_DEST_DIR, $relative_path);

    # The output directory should never ever be called "*Defs/*".  It's all singular.
    $output_file =~ s!Defs([\//])!Def$1!g;
    $output_file = file($output_file);

    # Auto-generate directories
    $output_file->dir->mkpath(1, 0755);

    # Blacklist check
    return if any {
        my $chk = $_;
        ref $chk eq 'Regexp' ? $relative_path =~ $chk : $relative_path eq $chk;
    } @FILE_BLACKLIST;

    # Never overwrite files

    ### DEBUG: To fix some incorrectly deleted dupe keys
    #if (-e $output_file && $ext eq 'xml') {
    #    $output_file =~ s!\.xml!_Repair.xml!;
    #    $output_file = file($output_file);
    #}

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
                my $text = $child_node->text;
                my $new_text;

                _check_xml_node_key( check_then_delete => $child_node, $input_file ) || next;

                #warn "NODE: $text\nTYPE: ".$child_node->name."\nPARENT TYPE: ".$child_node->parent->name."\nGRANDPARENT TYPE: ".$child_node->parent->parent->name."\n";

                # RulesFiles aren't actually language strings.  They are prefix key to filename mappings.
                next if $child_node->parent->name eq 'li' && $child_node->parent->parent->name =~ /\.rulePack\.rulesFiles$/;

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

                $new_text =~ s/^\s+|\s+$//g;

                $child_node->set_text($new_text);

                _check_xml_node_key( add => $child_node, $input_file );
            }
        }

        # If we deleted down to nothing, skip this entire file
        if (!$root->has_children) {
            say "No unique strings to parse!\n" if $DEBUG >= 1;
            return;
        }

        say "Writing XML file: $output_file" if $DEBUG >= 1;

        my $out = $output_file->open('>:encoding(UTF-8)') || die "Can't open $output_file for writing: $!";
        $xml->print($out);
        $out->close;
        $xml->purge;
    }
    elsif ($ext eq 'txt') {
        my $in  = $input_file ->open('<:encoding(UTF-8)') || die "Can't open $input_file for reading: $!";

        # Keep this buffered to prevent writing until the end
        my @out;

        while (defined( my $line = $in->getline )) {
            $line =~ s/\r//g;       # strip newline and re-print it later
            $line =~ s/^\N{BOM}//;  # somebody set us up the BOM

            if ($line =~ m!^\s*//\s*|^\s*$!) {
                # skip comments or blank lines
                push @out, $line;
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
                    local $PoorlyTranslateUtils::NUM_OF_LANGUAGE_STEPS = $PoorlyTranslateUtils::NUM_OF_LANGUAGE_STEPS * 2;
                    $new_text = poorly_translate_text($lang_code, $line);
                }

                push @out, $line unless lc $new_text eq lc $previous_text;
                $previous_text = $new_text;
            }
        }
        $in->close;

        say "Writing TXT file: $output_file" if $DEBUG >= 1;

        my $out = $output_file->open('>:encoding(UTF-8)') || die "Can't open $output_file for writing: $!";
        $out->print("\N{BOM}");
        $out->say($_) for @out;
        $out->close;
    }
    else {
        die "Unknown extension: $ext";
    }

    say "\n" if $DEBUG >= 1;
}
