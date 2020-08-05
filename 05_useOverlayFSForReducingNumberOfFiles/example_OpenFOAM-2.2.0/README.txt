For executing the 2.2.0 example, use the set of scripts that already exists
in the directory example_OpenFOAM-2.4.0, EXCEPT the D.runFOAM.

That is, the secuence of command lines (using debugq for execution) should be:
zeus-1:example_OpenFOAM-2.2.0> sbatch ../example_OpenFOAM-2.4.0/A.extractAndAdpatTutorial.sh
zeus-1:example_OpenFOAM-2.2.0> sbatch -p debugq ../example_OpenFOAM-2.4.0/B.decomposeFoam.sh
zeus-1:example_OpenFOAM-2.2.0> sbatch ../example_OpenFOAM-2.4.0/C.setupOverlayFoam.sh
zeus-1:example_OpenFOAM-2.2.0> sbatch -p debugq ./D.runFoam.sh
zeus-1:example_OpenFOAM-2.2.0> sbatch -p debugq ../example_OpenFOAM-2.4.0/E.reconstructFromOverlay.sh

Note that the use of the copyq partition is set within the scripts for steps A.and C.

The difference of script D.runFoam.sh is explained within the script. Basically, for version 2.2.0 there is a need to copy additional dictionaries into the overlayFS files.

The rest of specific settings for the 2.2.0 example is within the files:
caseSettingsFoam.sh
imageSettingsSingularity.sh
