################################################################################
# bitstream.tcl - generowanie bitstreamu.
#
# Wejscie : $OUTDIR/post_route.dcp
# Wyjscie : $OUTDIR/$TOP.bit
################################################################################
source [file dirname [info script]]/common.tcl

naglowek "BITSTREAM: $TOP"

open_checkpoint $OUTDIR/post_route.dcp
write_bitstream -force $OUTDIR/$TOP.bit

naglowek "BITSTREAM OK -> $OUTDIR/$TOP.bit"
