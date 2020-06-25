#!/bin/bash

#---------------------------------------------------------------
#---------------------------------------------------------------
function copyIntoOverlayII {
#Copy the source into the overlay* files
#
#This function receives No Global variables:
#
#This function receives the following arguments:
local sourceString=$1
local destinyString=$2
local foam_numberOfSubdomains=$3 #the number of subdomains in the OpenFOAM decomposition
local replace=$4 #Replace files/directories if they already exist? "true" or "false"
#
#IMPORTANT:#It needs to be called like:
#copyIntoOverlayII "$sourceStringOrg" "$destinyStringOrg" "$foam_numberOfSubdomainsOrg" "$replaceOrg"
#The source and destiny strings my contain the for counter '${ii}', but it needs to be defined with single quotes
#to avoid evaluation. The same for wildcards as '*'
#Evaluation is performed within the for loop inside the function
#For example,
#copyIntoOverlayII 'bak.processor${ii}/*' "$insideDir/"'processor${ii}/' "$foam_numberOfSubdomains" "true"
#
#No global variables are created back
#
#The function returns 0 if successful and other if the test failed 
#(return value should be catch with $? immediately after usage)
#
#...............................................................
local cpOptions=""
if [ "$replace" == "false" ]; then
   cpOptions="-r"
else
   cpOptions="-rf"
fi
echo "replace=$replace, then using the follwing options for the copy:cp $cpOptions"

echo "Copying files into the overlays"
local ii=0
local rnd=$RANDOM
for ii in $(seq 0 $(( foam_numberOfSubdomains - 1 ))); do
   local name=$rnd.$ii
   echo "Copy $ii: Writing into overlay${ii}, job-name=$name"
   eval sourceStringII=$sourceString
   echo "sourceStringII=$sourceStringII"
   eval destinyStringII=$destinyString
   echo "destinyStringII=$destinyStringII"
   srun -n 1 -N 1 --job-name=$name --mem-per-cpu=0 --exclusive singularity exec --overlay overlay${ii} docker://ubuntu:18.04 cp $cpOptions $sourceStringII $destinyStringII &
done
wait
for ii in $(seq 0 $(( foam_numberOfSubdomains - 1 ))); do
   local name=$rnd.$ii
   local res=$(sacct --jobs=$SLURM_JOB_ID --format=JobID,JobName,ExitCode | grep "$name" | awk '{ print $3 }')
   if [ "$res" == "0:0" ]; then
      echo "Copy $ii was successful. Exit status of srun job $name = $res"
   else
      echo "Copy $ii was NOT successful. Exit status of srun job $name = $res"
      return -1
   fi
done
return 0
}
#End ===========================================================


#---------------------------------------------------------------
#---------------------------------------------------------------
function copyResultsIntoBak {
#Copy the indicated Time results from the interior of overlay* files into the bak.procesors* directories
#
#This function receives No Global variables:
#
#This function receives the following arguments:
local insideDir=$1 #the root directory where results are going to be written inside the overlays
local foam_numberOfSubdomains=$2 #the number of subdomains in the OpenFOAM decomposition
local replace=$3 #Replace folders if they already exist? "true" or "false"
shift 3
local arrayHere=("$@") #has the array of the times to be transferred
#
#IMPORTANT:#It needs to be called like:
#copyResultsIntoBak "$insideDirOrg" "$foam_numberOfSubdomainsOrg" "$replaceOrg" "${arrayOrg[@]}"
#IMPORTANT:Note that the original array from the calling scritpt needs to be expanded as an argument
#
#No global variables are created back
#
#The function returns 0 if successful and other if the test failed 
#(return value should be catch with $? immediately after usage)
#
#...............................................................
echo "Copying files from the overlays into the bak.processors directories"
local jj=0
for jj in ${arrayHere[@]}; do
   #Checking if the folder already exists in bak.processor0 
   local proceed="true"
   if [ -d ./bak.processor0/${jj} ]; then
      if [ "$replace" == "false" ]; then
         echo "Directory bak.processor0/${jj} already exists."
         echo "Setting is replace=$replace. So time folder will not be replaced with the overlay0 content."
         proceed="false"
      else
         echo "Directory bak.processor0/${jj} already exists."
         echo "Setting is replace=$replace. So time folder will be overwritten with the overlay0 content."
      fi
   fi
   if [ "$proceed" == "true" ]; then
      echo "Copying time ${jj} to all the bak.procesors"
      local ii
      for ii in $(seq 0 $((foam_numberOfSubdomains -1))); do
         echo "Writing in bak.processor${ii}"
         srun -n 1 -N 1 --mem-per-cpu=0 --exclusive singularity exec --overlay overlay${ii} docker://ubuntu:18.04 cp -r $insideDir/processor${ii}/${jj} ./bak.processor${ii}/ &
      done
      wait
   fi
done
#Testing at least for bak.processor0
echo "Checking that indicated time directories are present in bak.processor0"
for jj in ${arrayHere[@]}; do
   if ! [ -d bak.processor0/${jj} ]; then
      echo "Time directory ${jj} is not in bak.procesor0"
      return 1
   fi
done
return 0
}
#End ===========================================================


#---------------------------------------------------------------
#---------------------------------------------------------------
function createInsideProcessorDirs {
#Creating inside processor* directories inside the overlayFS
#
#This function receives No Global variables:
#
#This function receives the following arguments:
local insideDir=$1 #the root directory where results are going to be written inside the overlays
local foam_numberOfSubdomains=$2 #the number of subdomains in the OpenFOAM decomposition
#
#No global variables are created back
#
#The function returns 0 if successful and other if the test failed 
#(return value should be catch with $? immediately after usage)
#
#...............................................................
#Checking if the directories already exist
echo "Checking if $insideDir/processor0 directory is already there"
srun -n 1 -N 1 singularity exec --overlay overlay0 docker://ubuntu:18.04 ls -dlh $insideDir/processor0
local success=$?
if [ "$success" -eq 0 ]; then
   echo "Directory $insideDir/processor0 already exists. No further internal creation or deletion will be done"
   return 222
fi
echo "Directory $insideDir/processor0 does not exist. Then will proceed with creation"

#Creating the directories inside
echo "Creating the directories inside the overlays"
local ii
for ii in $(seq 0 $(( foam_numberOfSubdomains - 1 ))); do
   echo "Creating processor${ii} inside overlay${ii}"
   srun -n 1 -N 1 --mem-per-cpu=0 --exclusive singularity exec --overlay overlay${ii} docker://ubuntu:18.04 mkdir -p $insideDir/processor${ii} &
done
wait
#Testing and returning the value of the test:
srun -n 1 -N 1 singularity exec --overlay overlay0 docker://ubuntu:18.04 ls -dlh $insideDir/processor0
return $?
}
#End ===========================================================



#---------------------------------------------------------------
#---------------------------------------------------------------
function createOverlay0 {
#Creating a first overlay file (overlay0)
#
#This function receives No Global variables:
#
#This function receives the following arguments:
local overlaySizeGb=$1 #the size of the file as a first argument (considered in Gb)
#
#No global variables are created back
#
#The function returns 0 if successful and other if the test failed 
#(return value should be catch with $? immediately after usage)
#
#...............................................................
#Checking if an overlay0 already exists
if [ -f overlay0 ]; then
   echo "A file named overlay0 already exists."
   echo "Aborting the creation of overlay0 file in order to avoid loss of information"
   echo "Check your overlay files and content, and remove them from the working directory first, if new overlay0 is needed"
   return 222
fi

#Creating the overlay0
#(Needs to use ubuntu:18.04 or higher to use the -d <root-dir> option to make them writable by simple users)
echo "Creating the overlay0 file"
echo "The size in Gb is overlaySizeGb=$overlaySizeGb"
if [ $overlaySizeGb -gt 0 ]; then
   local countSize=$(( overlaySizeGb * 1024 * 1024 ))
   srun -n 1 -N 1 singularity exec docker://ubuntu:18.04 bash -c " \
        mkdir -p overlay_tmp/upper && \
        dd if=/dev/zero of=overlay0 count=$countSize bs=1024 && \
        mkfs.ext3 -d overlay_tmp overlay0 && rm -rf overlay_tmp \
        "
else
   echo "Variable overlaySizeGb was not set correctly"
   echo "In theory, this should have been set together with the singularity settings"
fi 
#Testing and returning the value of the test:
srun -n 1 -N 1 singularity exec --overlay overlay0 docker://ubuntu:18.04 ls -lh overlay0
return $?
}
#End ===========================================================

#---------------------------------------------------------------
#---------------------------------------------------------------
function getIndex {
#Function to find the index in an array where value is exactly equal
#
#This function receives No Global variables:
#
#This function receives the following arguments:
local value=$1 #The value we are looking for
shift
local arrayHere=("$@") #The array to be inspected. (Needs to be expanded in the call, see below)
#IMPORTANT, array needst to be already sorted in increasing order
#
#No global variables are created back
#
#IMPORTANT:The function retuns the index value with an echo, so it needs to be received with $().
#So, it needs to be called like:
#index=$(getIndex "$value" "${arrayOrg[@]}")
#
#The function success or failure returns 0 if successful and other if the test failed 
#(return value should be catch with $? immediately after usage)
#
#...............................................................
local ii
for ii in "${!arrayHere[@]}"; do
   if [ $(echo "${arrayHere[$ii]} == $value" | bc -l) -eq 1 ]; then
      echo "${ii}"
      return 0
   fi
done
echo "-1"
return 255
} 
#End ===========================================================

#---------------------------------------------------------------
#---------------------------------------------------------------
function getIndexGE {
#Function to find the index in an array where value is greater or equal
#
#This function receives No Global variables:
#
#This function receives the following arguments:
local value=$1 #The value we are looking for
shift
local arrayHere=("$@") #The array to be inspected. (Needs to be expanded in the call, see below)
#IMPORTANT, array needst to be already sorted in increasing order
#
#No global variables are created back
#
#IMPORTANT:The function retuns the index value with an echo, so it needs to be received with $().
#So, it needs to be called like:
#index=$(getIndexGE "$value" "${arrayOrg[@]}")
#
#The function success or failure returns 0 if successful and other if the test failed 
#(return value should be catch with $? immediately after usage)
#
#...............................................................
local ii
for ii in "${!arrayHere[@]}"; do
   if [ $(echo "${arrayHere[$ii]} >= $value" | bc -l) -eq 1 ]; then
      echo "${ii}"
      return 0
   fi
done
echo "-1"
return 255
} 
#End ===========================================================

#---------------------------------------------------------------
#---------------------------------------------------------------
function getIndexLE {
#Function to find the index in an array where value is less or equal
#
#This function receives No Global variables:
#
#This function receives the following arguments:
local value=$1 #The value we are looking for
shift
local arrayHere=("$@") #The array to be inspected. (Needs to be expanded in the call, see below)
#IMPORTANT, array needst to be already sorted in increasing order
#
#No global variables are created back
#
#IMPORTANT:The function retuns the index value with an echo, so it needs to be received with $().
#So, it needs to be called like:
#index=$(getIndexLE "$value" "${arrayOrg[@]}")
#
#The function success or failure returns 0 if successful and other if the test failed 
#(return value should be catch with $? immediately after usage)
#
#...............................................................
local nLast=${#arrayHere[@]}
local ii
for ii in $(seq $((nLast -1)) -1 0); do
   if [ $(echo "${arrayHere[$ii]} <= $value" | bc -l) -eq 1 ]; then
      echo "${ii}"
      return 0
   fi
done
echo "-1"
return 255
} 
#End ===========================================================

#---------------------------------------------------------------
#---------------------------------------------------------------
function generateReconstructArray {
#Generate the global array of times to be reconstructed
#
#This function receives No Global variables:
#
#This function receives the following arguments:
local reconstructTimes="$1" #the indication of the reconstruct times we are looking for
local whatSource="$2" #If the value is "bak", then results in bak.processors* will be used.
                     #Otherwise, it indicates where results are being created inside the overlay* files
#
#Examples of the 5 accepted formats for the reconstructTimes parameter are:
#reconstructTimes="all" #Means, all the available times will be included in the array generated
#reconstructTimes="-5" #Means, the last 5 available times will be included
#reconstructTimes="60.1" #Means the exact given time will be included if available
#reconstructTimes="50,60,70,80,90" #Means, the exact times in the list will be included if available
#reconstructTimes="55.2:69" #Means the available times within the range will be included

#
#These global variables are created back
unset arrayReconstruct
arrayReconstruct[0]=-1 #Global array with the times to be reconstructed (will grow to size needed)
#
#The function returns 0 if successful and other if the test failed 
#(return value should be catch with $? immediately after usage)
#
#...............................................................
#Generating a list of existing time directories
if [ "$whatSource" == "bak" ]; then
   echo "Creating a list of existing time directories in ${whatSource}.processor0"
   ls -dt ${whatSource}.processor0/[0-9]* | sed "s,${whatSource}.processor0/,," > listTimes.$SLURM_JOBID
else
   echo "Creating a list of existing time directories in ${whatSource}/processor0 of overlay0"
   srun -n 1 -N 1 --mem-per-cpu=0 --exclusive singularity exec --overlay overlay0 docker://ubuntu:18.04 bash -c \
       "ls -dt $whatSource/processor0/[0-9]* | sed 's,$whatSource/processor0/,,' > listTimes.$SLURM_JOBID"
fi
sort -n listTimes.$SLURM_JOBID -o listTimesSorted.$SLURM_JOBID
rm listTimes.$SLURM_JOBID
local i=0
local timeDirArr[0]=-1
echo "Existing times are:"
while read textTimeDir; do
   timeDirArr[$i]=$textTimeDir
   echo "The $i timeDir is: ${timeDirArr[$i]}"
   ((i++))
done < listTimesSorted.$SLURM_JOBID
local nTimeDirectories=$i
if [ $nTimeDirectories -eq 0 ]; then
   echo "NO time directories available for the case in overlay0"
else
   echo "The maxTimeSeen=${timeDirArr[$((nTimeDirectories - 1))]}"
fi


# Generate the reconstruction array 
echo "Generating the reconstruction array (global array) \"arrayReconstruct\""
echo "Given setting is reconstructTimes=$reconstructTimes"
local nReconstruct=0
local ii=0
local re='^[+-]?[0-9]+([.][0-9]+)?$'
local reInt='^[+-]?[0-9]+$'
if [[ $reconstructTimes =~ $re ]]; then
   if [ $(echo "$reconstructTimes >= 0" | bc -l) -eq 1 ]; then #if a single positive time is given, pick it
      echo "Using the single time give notation"
      local hereTime=$reconstructTimes
      local indexHere=$(getIndex "$hereTime" "${timeDirArr[@]}")
      if [ $indexHere -ge 0 ] && [ $indexHere -lt $nTimeDirectories ] ; then
         arrayReconstruct[$nReconstruct]="$hereTime"
         (( nReconstruct++ ))
      fi
   elif [[ $reconstructTimes =~ $reInt ]]; then #if negative (-N), pick the last N times
      echo "Using the reconstructTimes=-N notation"
      echo "Picking the last N=$(( -1 * reconstructTimes)) existing times inside the overlays"
      for ii in $(seq $reconstructTimes -1); do
         local indexHere=$((nTimeDirectories + ii))
         if [ $indexHere -ge 0 ] && [ $indexHere -lt $nTimeDirectories ] ; then
            arrayReconstruct[$nReconstruct]=${timeDirArr[$((nTimeDirectories + ii))]}
            (( nReconstruct++ ))
         fi
      done
   fi
else
   if [ "$reconstructTimes" = "all" ]; then #pick all the existing times
      echo "Using the reconstructTimes=\"all\" notation"
      echo "Picking all the existing times inside the overlays for reconstruct"
      for ii in $(seq 0 $((nTimeDirectories - 1))); do
         arrayReconstruct[$nReconstruct]=${timeDirArr[$ii]}
         (( nReconstruct++ ))
      done
   elif [[ "$reconstructTimes" == *":"* ]]; then #if using notation with "first:last", pick from start to end (no code to deal with increment in notation)
      echo "Using the range notation reconstructTimes=first:last"
      echo "Picking all the existing times within the range inside the overlays"
      local firstTime=${reconstructTimes%%:*}
      local lastTime=${reconstructTimes##*:}
      local indexFirst=$(getIndexGE "$firstTime" "${timeDirArr[@]}")
      local indexLast=$(getIndexLE "$lastTime" "${timeDirArr[@]}")
      echo "firstTime=$firstTime indexFirst=$indexFirst"
      echo "lastTime=$lastTime indexLast=$indexLast"
      for ii in $(seq $indexFirst $indexLast); do
         if [ $ii -ge 0 ] && [ $ii -lt $nTimeDirectories ] ; then
            arrayReconstruct[$nReconstruct]=${timeDirArr[$ii]}
            (( nReconstruct++ ))
         fi
      done
   elif [[ "$reconstructTimes" == *","* ]]; then #if using notation with comma separated list "a,b,c", pick them
      echo "Using the comma separated list notation"
      local nLast=$(awk -F "," '{print NF-1}' <<< $reconstructTimes)
      local rest=$reconstructTimes
      for ii in $(seq $nReconstruct $nLast); do
         local hereTime=${rest%%,*}
         local indexHere=$(getIndex "$hereTime" "${timeDirArr[@]}")
         if [ $indexHere -ge 0 ] && [ $indexHere -lt $nTimeDirectories ] ; then
            arrayReconstruct[$nReconstruct]="$hereTime"
            (( nReconstruct++ ))
         fi
         rest=${rest#*,}
      done
   fi
fi

#Checking reconstructArray settings:
echo "The created reconstruction array has:"
echo "nReconstruct=$nReconstruct"
if [ $nReconstruct -gt 0 ]; then
   nLast=$(( nReconstruct - 1 ))
   for ii in $(seq 0 $nLast); do
      echo "arrayReconstruct[$ii]=${arrayReconstruct[ii]}"
   done
   rm listTimesSorted.$SLURM_JOBID
   return 0
else
   echo "Global arrayReconstruct could not be created with those settings. Check what failed"
   if [ "$whatSource" == "bak" ]; then
      echo "The list of existing times in ${whatSource}.processor0 is in listTimesSorted.$SLURM_JOBID file"
   else
      echo "The list of existing times inside overlay0 ($whatSource/processor0) is in listTimesSorted.$SLURM_JOBID file"
   fi
   return 1
fi
}
#End ===========================================================

#---------------------------------------------------------------
#---------------------------------------------------------------
function pointToBak {
#Creating soft links to point towards the bak.processor* directories
#
#This function receives No Global variables:
#
#This function receives the following arguments:
local foam_numberOfSubdomains=$1 #the number of subdomains in the OpenFOAM decomposition
#
#No global variables are created back
#
#The function returns 0 if successful and other if the test failed 
#(return value should be catch with $? immediately after usage)
#
#...............................................................
#Removing any softling
echo "First removing existing soft links"
local linkList=$(find . -type l -name "proc*")
for ll in $linkList; do
    rm $ll
done

#Creating the broken soft links
echo "Creating the soft links to point towards the bak.processor* directories"
for ii in $(seq 0 $(( foam_numberOfSubdomains -1 ))); do
    echo "Linking to bak.procesor${ii}"
    srun -n 1 -N 1 --mem-per-cpu=0 --exclusive ln -s bak.processor${ii} processor${ii} &
done
wait

#Testing and returning the value of the test:
ls -dlh processor0
return $?
}
#End ===========================================================

#---------------------------------------------------------------
#---------------------------------------------------------------
function pointToOverlay {
#Creating soft links to point towards directories inside the overlayFS files
#These links and directories will be recognized by each mpi instance of the container
#(Initially these links will appear broken as they are pointing towards the interior of the overlay* files.
# They will only be recognized within the containers)
#
#This function receives No Global variables:
#
#This function receives the following arguments:
local insideDir=$1 #the root directory where results are going to be written inside the overlays
local foam_numberOfSubdomains=$2 #the number of subdomains in the OpenFOAM decomposition
#
#No global variables are created back
#
#The function returns 0 if successful and other if the test failed 
#(return value should be catch with $? immediately after usage)
#
#...............................................................
#Removing any softling
echo "First removing existing soft links"
local linkList=$(find . -type l -name "proc*")
for ll in $linkList; do
    rm $ll
done

#Creating the soft links (will initially appear as broken)
echo "Creating the soft links to point towards the interior of the overlay files"
local ii=0
for ii in $(seq 0 $(( foam_numberOfSubdomains -1 ))); do
    echo "Linking to $insideDir/processor${ii} in overlay${ii}"
    srun -n 1 -N 1 --mem-per-cpu=0 --exclusive ln -s $insideDir/processor${ii} processor${ii} &
done
wait

#Testing and returning the value of the test:
srun -n 1 -N 1 singularity exec --overlay overlay0 docker://ubuntu:18.04 ls -dlh processor0
return $?
}
#End ===========================================================
