#!/bin/bash
set -euo pipefail
################################################################################
## This will make all (pulseaudio) sound currently playing mono.              ##
##                                                                            ##
## It does this by creating a new remapped "monosound" sink for each existing ##
## sink. Then it moves every input over to the monosound sink corresponding   ##
## to the sink the input is currently using.                                  ##
################################################################################

SINKS=$(pacmd list-sinks)
MASTERS=$(grep -oP 'name:\s<\K.*(?=>)' <<< "$SINKS" | grep -v "monosound")
echo "Masters:"
echo "$MASTERS"

# Create a monosound sink for each non-monosound sink
while read -r MASTER; do
	# The name of the remapped sink
	REMAPPED="$MASTER-monosound"
	if ! grep -q "$REMAPPED" <<< "$SINKS"; then
		echo "Didn't find '$REMAPPED', creating"
		pacmd load-module module-remap-sink sink_name="$REMAPPED" master="$MASTER" channels=2 channel_map=mono,mono
	fi
done <<< "$MASTERS"

# This will output all inputs, with only two lines each (hopefully)
# The first line will be the input index, and the second will be the input's sink
# Example entry:
#	index: 8
#		sink: 15 <bluez_sink.28_11_A5_43_83_0B.a2dp_sink-monosound>
# Then sed merges the two into one line, to get something like
# index: 8	sink: 15 <bluez_sink.28_11_A5_43_83_0B.a2dp_sink-monosound>
# (I wish pacmd could output json so I could just use jq)
INPUTS=$(pacmd list-sink-inputs | grep '^\s\+\(index\|sink\): ' | sed '/^\s\+index: /{N;s/\n//;}')

echo "Inputs:"
echo "$INPUTS"
while read -r INPUT; do
	echo "Input: $INPUT"
	# This regex changes the merged INPUT entry from above into just two columns
	# The first with the input index, and the second with the sink name
	TMP=$(sed -n 's/^\s*index:\s\+\([0-9]\+\)\s\+sink:\s\+[0-9]\+\s\+<\(\S\+\)>$/\1\t\2/p' <<< "$INPUT")

	# If the line didn't match the regex, we'll get emptry string out
	if [[ "$TMP" == "" ]]; then
		echo "Input line didn't match regex, skipping"
		continue
	fi

	INDEX=$(awk '{print $1}' <<< "$TMP")
	SINK=$(awk '{print $2}' <<< "$TMP")
	REMAPPED="$SINK-monosound"

	if [[ "$SINK" == *monosound ]]; then
		echo "$INDEX was already set to monosound, skipping"
		continue
	fi

	echo "Moving $INDEX to $REMAPPED"
	pacmd move-sink-input "$INDEX" "$REMAPPED"
done <<< "$INPUTS"

echo "Finished successfully"
