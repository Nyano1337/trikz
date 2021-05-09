INSTALLATION AND USAGE:
------

To make use of this updated code (all in source) you will need to be running BotoX's fork of Sourcemod, OutputInfo (BotoX's version), SendProxy Manager and DHooks (Supporting Detours)

DHooks (detour support) can be found here:
[https://forums.alliedmods.net/showpost.php?p=2588686&postcount=589]

SendProxy Manager can be built from this source:
[https://github.com/SlidyBat/sendproxy]
(any obtained version will do!)

and OutputInfo from this source:
[https://gogs.botox.bz/CSSZombieEscape/sm-ext-outputinfo]

BotoX's Sourcemod can be found here:
[https://github.com/BotoX/sourcemod]

### !!! USE BRANCH 1.11-fork !!!
https://github.com/Ciallo-Ani/sourcemod

To Build SourceMod follow these instructions replacing the sourcemod repository with BotoX's version:
[https://wiki.alliedmods.net/Building_SourceMod]
(I recommend Clang on Linux)

To build the extensions after building sourcemod simply change to the extensions dir within the sourcemod source and follow these instructions per extension:
```
mkdir build
cd build
python ../configure.py
ambuild
```

The extension files will be placed inside of this build folder to be copied to your sourcemod installation.

For SendProxy I recommend building with CSS support specifically using the following variation:
```
mkdir build
cd build
python ../configure.py --sdks css
ambuild
```

Additionall you will need a MySQL database for this!

Once you have all the requirements, simply compile the provided plugins and upload them along with the configs (my configs are provided since some features of bTimes are not well suited to Trikz).

Then add an entry to your addons/sourcemod/configs/databases.cfg as follows:
```
	"timer"
	{
		"driver"			"mysql"
		"host"				"localhost"
		"database"			"unloze_trikz"
		"user"				"unloze_trikz"
		"pass"				"tcSF5nn9kRp57YWuTWBK"
	}
```

Remember to configure your own ranks and sounds in the addons/sourcemod/configs/timer folder in place of my own!
