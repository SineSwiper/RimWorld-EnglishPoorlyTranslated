Quick Start Guide
=================
1. Sign up for a free Google Cloud Platform trial here: https://console.cloud.google.com/freetrial

2. Create a Cloud Translation API key.

3. Check the Quotas page for the API and make sure the per-minute and per-day limits are unlimited,
   or at least set to a reasonably high limit.  If you run into Limit Exceeded messages, check
   here.

4. Make sure you have a decent version of Perl (at least 5.14, preferably higher).  Run the
   following to install the required modules: cpanm --install-deps .

5. Put the English language files into input/Core/Languages/English.

6. Untar another language set (like German) into input/Core/Languages/<language>.

7. You can put entire mod directories in input/<mod_name_or_SteamID>.  A command like this will 
   clean out most everything except the Language files, if you were copying data:

   rm -rf */{1.1/,v1.1/,''}{Assemblies,Textures,Sounds,Patches,Defs,Source,News,Versions,RimThemes,Materials,Screenshots} */{0.19,1.0,v1.0} */[oO]ld* */.git */*.zip */*.md */LICENSE */LoadFolders.xml */About/*.{jpg,gif,png,psd,xcf}

8. Look at the global variables in poorly-translate.pl and lib/PoorlyTranslateUtils.pm.  Tweak
   whatever you like, especially the @PROCESS_LANGUAGES.

9. Set an environment variable called GOOGLE_TRANSLATE_API_KEY to the API key you set up on the
   Credentials screen of the Cloud Translation API.

10. Run ./poorly-translate.pl.

11. After it's done, run ack/grep or a text searcher of your choice to see if anything needs
    fixing up.

12. When you're happy with the result, run ./output-tarball.sh, which will dump a tarball into the
    1.1/Languages folder.

Notes
=====
I burned through all $300 of my free trial, but that was after a ton of restarts and testing, as
well as running though a large mod collection.  A full run of Core should only take a third of
that.

The 'poorly-translate-phrase' utility is good for translating smaller phrases for single element
repairing.  Unlike the main translate script, it has a proper CLI.

You can Ctrl+C, restart the translate script, and it will pick up where you left off, including
merging XML files where needed.  The script does a pretty good job of splicing at the right place
and using substition variables, but it's not perfect.  It will try to start over translations on
bad results, or warn you of potential issues.

The English language files that come with RimWorld core isn't a full set, so you'll need a
secondary language to augment that.  Although, certain languages have their quirks that might not
translate right, or need adjustments to the files.  For example, German likes to use a lot of
compound words that don't translate well, and it has a bunch of adjective suffixes that may appear
in ruleStrings.

Mod translation files may have some odd XML errors that need correcting.  Somehow, they work or
just get skipped in RimWorld.  XML::Twig (with its current settings) is stricter, so fix them as
you go.

Yes, I realize global variables are lazy.  Should have used YAML, but ¯\_(ツ)_/¯
