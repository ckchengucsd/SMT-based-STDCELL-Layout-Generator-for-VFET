#! /usr/bin/perl

use strict 'vars';
use strict 'refs';
use strict 'subs';

use POSIX;

use Cwd;

sub combine; sub combine_sub;
sub combine {
	my ($list, $n) = @_;
	die "Insufficient list members" if $n > @$list;

	return map [$_], @$list if $n <= 1;

	my @comb;

	for (my $i = 0; $i+$n <= @$list; ++$i){
		my $val = $list->[$i];
		my @rest = @$list[$i+1..$#$list];
		push @comb, [$val, @$_] for combine_sub \@rest, $n-1;
		if($i==0){
			last;
		}
	}

	return @comb;
}
sub combine_sub {
	my ($list, $n) = @_;
	die "Insufficient list members" if $n > @$list;

	return map [$_], @$list if $n <= 1;

	my @comb;

	for (my $i = 0; $i+$n <= @$list; ++$i){
		my $val = $list->[$i];
		my @rest = @$list[$i+1..$#$list];
		push @comb, [$val, @$_] for combine_sub \@rest, $n-1;
	}

	return @comb;
}

### Revision History : Ver 1.0 #####
# 2022-04-30 Initial Release
### Pre-processing ########################################################
my $ARGC        = @ARGV;
my $workdir     = getcwd();
my $outdir      = "$workdir/inputsSMT";
my $infile      = "";

my $numTier     = 1;		# Number of stacking tiers
my $numHTrack = 5;			# Number of Horizontal Routing Tracks, Total Routing Track = numHTrack + 2(power)
my $trackPFET = 2;			# Location of horizontal track for PFET placement on Tier1 layer
my $trackNFET = 4;			# Location of horizontal track for PFET placement on Tier1 layer
my $BS        = 0;			# Set Symmetry Removal Constraints, 0:Disable, 1:Enable
my $CP		  = 0;			# Set Cell Partitioning Constraints, 0:Disable, 1:Enable
my $LC		  = 0;			# Set localization constraints, 0:Disable, 1:Enable
my $LT		  = 0;			# Set localization tolerance
my $MPO_Parameter = 2;		# Minimum Number of Pin Opening

my $MAR_Parameter = 1;		# Minimum Area
my $EOL_Parameter = 0;		# End-of-line Spacing

if ($ARGC != 7) {
    print "\n*** Error:: Wrong CMD";
    print "\n   [USAGE]: ./PL_FILE [inputfile_pinLayout] [NumTier] [MPO] [BS] [CP] [LC] [LT]\n\n";
    exit(-1);
} else {
    $infile             = $ARGV[0];
	$numTier			= $ARGV[1];
	$MPO_Parameter		= $ARGV[2];
	$BS					= $ARGV[3];
	$CP					= $ARGV[4];
	$LC					= $ARGV[5];
	$LT					= $ARGV[6];
}

if (!-e "./$infile") {
    print "\n*** Error:: FILE DOES NOT EXIST..\n";
    print "***         $workdir/$infile\n\n";
    exit(-1);
} else {
    print "\n";
    print "a   Version Info : 1.0 Initial Version\n";

    print "a        Design Parameters : [NumTier = $numTier]\n";
    print "a			              : [NumHTrack = $numHTrack, Track for 1 Tier PFET = $trackPFET, Track for 1 Tier NFET = $trackNFET], MPO=$MPO_Parameter\n";
    print "a						  : [BS = ".($BS==0?"Disabled":"Enabled").", CP = ".($CP==0?"Disabled":"Enabled").", LC = ".($LC==0?"Disabled":"Enabled(T=$LT)")."]\n\n";

    print "a   Generating SMT-LIB 2.0 Standard inputfile based on the following files.\n";
    print "a     Input Layout:  $workdir/$infile\n";
}


### Variable Declarations
my $numTrackH = 0;
my $numTrackV = 0;
my $numMetalLayer = 5;

### PIN variables
my @pins = ();
my @pin = ();
my $pinName = "";
my $pin_netID = ""; 
my $pin_instID = "";			
my $pin_type = "";		
my $pin_type_IO = "";		
my $pinIO = "";
my $pinIdx= 0;
my %h_pin_id = ();
my %h_pin_idx = ();
my %h_pinId_idx = ();
my %h_outpinId_idx = ();
my %h_pin_net = ();
my %h_pinName_type = ();
my %h_instIdx_S = ();
my %h_instIdx_G = ();
my %h_instIdx_D = ();

### NET variables
my @nets = ();
my @net = ();
my $netName = "";
my $netID = -1;
my $N_pinNets = 0;
my $numSinks = -1;
my $source_ofNet = "";
my @pins_inNet = ();
my @sinks_inNet = ();
my $totalNets = -1;
my $idx_nets = 0;
my $numNets_org = 0;
my %h_extnets = ();
my %h_idx = ();
my %h_outnets = ();
my %h_pwrnets = ();
my %h_netName_idx = ();

### Instance variables
my $numInstance = 0;
my $instName = "";
my $instType = "";
my $instWidth = 0;
my $instGroup = 0;
my $instY = 0;
my @inst = ();
my $lastIdxPMOS = -1;
my %h_inst_idx = ();
my @numFinger = ();
my $minWidth = 0;
my $numPowerPmos = 0;
my $numPowerNmos = 0;
my @inst_group = ();
my %h_inst_group = ();
my @inst_group_p = ();
my @inst_group_n = ();

my %h_mf = ();

my %h_preassign = ();

### Power Net/Pin Info
my $netVDD = -1;
my $netVSS = -1;
my $numVDDPin = 0;
my $numVSSPin = 0;

my $infileStatus = "init";

my %h_track = ();
### FET location assignment for each Tier according to the stack type
for my $i(0 .. $numTier-1){
	$h_track{$i."_P"} = $trackPFET;
	$h_track{$i."_N"} = $trackNFET;
}
# set num Metal Layer using num Tier
$numMetalLayer = $numTier * 2 + 1 + 1;

print "a     FET track assignment\n";
for my $i(0 .. $numTier-1){
	print "a     [Tier ".($i+1)."] PFET : ".$h_track{$i."_P"}."  NFET : ".$h_track{$i."_N"}."\n";
}

### Read Inputfile and Build Data Structure
open (my $in, "./$infile");
while (<$in>) {
    my $line = $_;
    chomp($line);

    ### Status of Input File
    if ($line =~ /===InstanceInfo===/) {
        $infileStatus = "inst";
    } 
    elsif ($line =~ /===NetInfo===/) {
        $infileStatus = "net";
		for(my $i=0; $i<=$#pins; $i++){
			if(exists($h_pin_net{$pins[$i][1]})){
				if($pins[$i][2] eq "s"){
					$h_pin_net{$pins[$i][1]} = $h_pin_net{$pins[$i][1]}." ".$pins[$i][0];
				}
				else{
					$h_pin_net{$pins[$i][1]} = $pins[$i][0]." ".$h_pin_net{$pins[$i][1]};
				}
			}
			else{
				$h_pin_net{$pins[$i][1]} = $pins[$i][0];
			}
		}
    }
    elsif ($line =~ /===PinInfo===/) {
        $infileStatus = "pin";
    }
    elsif ($line =~ /===PartitionInfo===/) {
        $infileStatus = "partition";
    }

    ### Infile Status: init
    if ($infileStatus eq "init") {
        if ($line =~ /Width of Routing Clip\s*= (\d+)/) {
            $numTrackV = $1;
            print "a     # Vertical Tracks   = $numTrackV\n";
            $numTrackH = $numHTrack + 2;
            print "a     # Horizontal Tracks = $numTrackH\n";
        }
    }

    ### Infile Status: Instance Info
    if ($infileStatus eq "inst") {
        if ($line =~ /^i   ins(\S+)\s*(\S+)\s*(\d+)/) {	
			$instName = "ins".$1;
			$instType = $2;
			$instWidth = $3;

			# detect multi-fingered FET
			my $insID = $1;
			if($insID =~ /(\S+)_(\d+)/){
				if(!exists($h_mf{$1})){
					my @tmp_arr = ();
					push(@tmp_arr, $numInstance);
					$h_mf{$1} = \@tmp_arr;
				}
				else{
					my @tmp_arr = $h_mf{$1};
					push(@{$tmp_arr[0]}, $numInstance);
					$h_mf{$1} = \@{$tmp_arr[0]};
				}
			}
			else{
				if(!exists($h_mf{$insID})){
					my @tmp_arr = ();
					push(@tmp_arr, $numInstance);
					$h_mf{$1} = \@tmp_arr;
				}
			}

			if($instType eq "NMOS"){
				if($lastIdxPMOS == -1){
					$lastIdxPMOS = $numInstance - 1;
				}
				$instY = $trackNFET;
			}
			else{
				$instY = $trackPFET;
			}
			push(@inst, [($instName, $instType, $instWidth, $instY)]);
			$h_inst_idx{$instName} = $numInstance;
			$numInstance++;
		}
    }

    ### Infile Status: pin
    if ($infileStatus eq "pin") {
		if ($line =~ /^i   pin(\d+)\s*net(\d+)\s*(\S+)\s*(\S+)\s*(\S+)\s*(\S+)\s*(\S+)/) {
			$pin_type_IO = $7;
		}
		if ($line =~ /^i   pin(\d+)\s*net(\d+)\s*(\S+)\s*(\S+)\s*(\S+)\s*(\S+)/) {
            $pinName = "pin".$1;
            $pin_netID = "net".$2; 
			$pin_instID = $3;
			$pin_type = $4;
            $pinIO = $5;

			if($pin_instID ne "ext"){
				if($pin_type eq "S"){
					$h_instIdx_S{$h_inst_idx{$pin_instID}} = $pinName;
				}
				if($pin_type eq "D"){
					$h_instIdx_D{$h_inst_idx{$pin_instID}} = $pinName;
				}
				if($pin_type eq "G"){
					$h_instIdx_G{$h_inst_idx{$pin_instID}} = $pinName;
				}

				@pin = ($pinName, $pin_netID, $pinIO, $inst[$h_inst_idx{$pin_instID}][3], $pin_instID, $pin_type);
				push (@pins, [@pin]);
			}
			elsif($pin_instID eq "ext"){
				my $tmp_pinY = -1;
				if($pin_type eq "VDD"){
					$netVDD = $2;
					$tmp_pinY = 0;
				}
				elsif($pin_type eq "VSS"){
					$netVSS = $2;
					$tmp_pinY = $numTrackH-1;
				}
				else{
					$tmp_pinY = -1;
				}
				@pin = ($pinName, $pin_netID, $pinIO, $tmp_pinY, $pin_instID, $pin_type);
				push (@pins, [@pin]);
				$h_outpinId_idx{$pinName} = $pinIdx;
				if($pin_type ne "VDD" && $pin_type ne "VSS"){
					$h_extnets{$2} = 1;
				}
				else{
					$h_pwrnets{$2} = 1;
				}
				if($pin_type_IO eq "O"){
					$h_outnets{$pin_netID} = 1;
				}
			} 
			$h_pin_id{$pin_instID."_".$pin_type} = $2;
			$h_pinId_idx{$pinName} = $pinIdx;
			$h_pinName_type{$pinName} = $pin_type;
			$pinIdx++;
        }
    }

    ### Infile Status: net
    if ($infileStatus eq "net") {
        if ($line =~ /^i   net(\S+)\s*(\d+)PinNet (.*)/) {
			$numNets_org++;
            $netID = $1;
            $netName = "net".$netID;
			my $numPin = $2;
			my $pinList = $3;
		
			@net = split /\s+/, $pinList;
			if(scalar(@net) != $numPin){
				print "[ERROR] Parsing Net Info : Net Information is not correct!! [$netName] NumPin=$numPin, NumListedPin=".(scalar(@net))."\n";
				exit(-1);
			}
			$N_pinNets = $#net+1;
			@pins_inNet = ();
			my $num_outpin = 0;
			for my $pinIndex_inNet (0 .. $N_pinNets-1) {
				push (@pins_inNet, $net[$pinIndex_inNet]);
			}
			$source_ofNet = $pins_inNet[$N_pinNets-1];
			$numSinks = $N_pinNets - 1;
			@sinks_inNet = ();
			for my $sinkIndex_inNet (0 .. $numSinks-1) {
				push (@sinks_inNet, $net[$sinkIndex_inNet]);
			}
			$numSinks = $numSinks - $num_outpin;
			@net = ($netName, $netID, $N_pinNets, $source_ofNet, $numSinks, [@sinks_inNet], [@pins_inNet]);
			$h_netName_idx{$netName} = $idx_nets;
			$h_idx{$netID} = $idx_nets;
			push (@nets, [@net]);

			if($netID == $netVDD){
				$numVDDPin = $numSinks;
			}
			if($netID == $netVSS){
				$numVSSPin = $numSinks;
			}
			$idx_nets++;
        }
    }

    ### Infile Status: Partition Info
    if ($CP == 1 && $infileStatus eq "partition") {
        if ($line =~ /^i   ins(\S+)\s*(\S+)\s*(\d+)/) {	
			$instName = "ins".$1;
			$instType = $2;
			$instGroup = $3;

			if(!exists($h_inst_idx{$instName})){
				print "[ERROR] Instance [$instName] in PartitionInfo not found!!\n";
				exit(-1);
			}
			my $idx = $h_inst_idx{$instName};

			push(@inst_group, [($instName, $instType, $instGroup)]);
			$h_inst_group{$idx} = $instGroup;
		}
    }
}
close ($in);

### Output Directory Creation, please see the following reference:
system "mkdir -p $outdir";

my $outfile     = "$outdir/".(split /\./, (split /\//, $infile)[$#_])[0]."_T$numTier.smt2";
print "a     SMT-LIB2.0 File:    $outfile\n";


my $totalPins = scalar @pins;
my $totalNets = scalar @nets;
print "a     # Pins              = $totalPins\n";
print "a     # Nets              = $totalNets\n";

print "a     # VDD/VSS Pins = $numVDDPin/$numVSSPin\n";

# Generating Instance Group Array
if ($CP == 1){
	my @inst_sorted = ();
	@inst_sorted = sort { (($a->[2] =~ /(\d+)/)[0]||0) <=> (($b->[2] =~ /(\d+)/)[0]||0) || $a->[2] cmp $b->[2] } @inst_group;

	my $prev_group_p = -1;
	my $prev_group_n = -1;
	my @arr_tmp_p = ();
	my @arr_tmp_n = ();
	my $minWidth_p = 0;
	my $minWidth_n = 0;
	my $isRemain_P = 0;
	my $isRemain_N = 0;
	for my $i(0 .. $#inst_sorted){
		if($h_inst_idx{$inst_sorted[$i][0]} <= $lastIdxPMOS){
			if($prev_group_p != -1 && $prev_group_p != $inst_sorted[$i][2]){
				push(@inst_group_p, [($prev_group_p, [@arr_tmp_p], $minWidth_p)]);
				@arr_tmp_p = ();
				$minWidth_p = 0;
			}
			push(@arr_tmp_p, $h_inst_idx{$inst_sorted[$i][0]});
			$prev_group_p = $inst_sorted[$i][2];
			$isRemain_P = 1;
			$minWidth_p+=1;
		}
		else{
			if($prev_group_n != -1 && $prev_group_n != $inst_sorted[$i][2]){
				push(@inst_group_n, [($prev_group_n, [@arr_tmp_n], $minWidth_n)]);
				@arr_tmp_n = ();
				$minWidth_n = 0;
			}
			push(@arr_tmp_n, $h_inst_idx{$inst_sorted[$i][0]});
			$prev_group_n = $inst_sorted[$i][2];
			$isRemain_N = 1;
			$minWidth_n+=1;
		}
	}
	if($isRemain_P == 1){
		push(@inst_group_p, [($prev_group_p, [@arr_tmp_p], $minWidth_p)]);
	}
	if($isRemain_N == 1){
		push(@inst_group_n, [($prev_group_n, [@arr_tmp_n], $minWidth_n)]);
	}
}

### VERTEX Generation
### VERTEX Variables
my %vertices = ();
my @vertex = ();
my $numVertices = -1;
my $vIndex = 0;
my $vName = "";
my @vADJ = ();
my $vL = "";
my $vR = "";
my $vF = "";
my $vB = "";
my $vU = "";
my $vD = "";
my $vFL = "";
my $vFR = "";
my $vBL = "";
my $vBR = "";

### DATA STRUCTURE:  VERTEX [index] [name] [Z-pos] [Y-pos] [X-pos] [Arr. of adjacent vertices]
### DATA STRUCTURE:  ADJACENT_VERTICES [0:Left] [1:Right] [2:Front] [3:Back] [4:Up] [5:Down] [6:FL] [7:FR] [8:BL] [9:BR]
for my $metal (0 .. $numMetalLayer-1) { 
    for my $row (0 .. $numTrackH-1) {
        for my $col (0 .. $numTrackV-1) {
            $vName = "m".$metal."r".$row."c".$col;
			if ($col == 0) { ### Left Vertex
				$vL = "null";
			} 
			else {
				$vL = "m".$metal."r".$row."c".($col-1);
			}
			if ($col == $numTrackV-1) { ### Right Vertex
				$vR = "null";
			}
			else {
				$vR = "m".$metal."r".$row."c".($col+1);
			}
			if ($row == 0) { ### Front Vertex
				$vF = "null";
			}
			else {
				$vF = "m".$metal."r".($row-1)."c".$col;
			}
			if ($row == $numTrackH-1) { ### Back Vertex
				$vB = "null";
			}
			else {
				$vB = "m".$metal."r".($row+1)."c".$col;
			}
			if ($metal == $numMetalLayer-1) { ### Up Vertex
				$vU = "null";
			}
			else {
				$vU = "m".($metal+1)."r".$row."c".$col;
			}
			if ($metal == 1) { ### Down Vertex
				$vD = "null";
			}
			else {
				$vD = "m".($metal-1)."r".$row."c".$col;
			}
			if ($row == 0 || $col == 0) { ### FL Vertex
				$vFL = "null";
			}
			else {
				$vFL = "m".$metal."r".($row-1)."c".($col-1);
			}
			if ($row == 0 || $col == $numTrackV-1) { ### FR Vertex
				$vFR = "null";
			}
			else {
				$vFR = "m".$metal."r".($row-1)."c".($col+1);
			}
			if ($row == $numTrackH-1 || $col == 0) { ### BL Vertex
				$vBL = "null";
			}
			else {
				$vBL = "m".$metal."r".($row+1)."c".($col-1);
			}
			if ($row == $numTrackH-1 || $col == $numTrackV-1) { ### BR Vertex
				$vBR = "null";
			}
			else {
				$vBR = "m".$metal."r".($row+1)."c".($col+1);
			}
            @vADJ = ($vL, $vR, $vF, $vB, $vU, $vD, $vFL, $vFR, $vBL, $vBR);
            @vertex = ($vIndex, $vName, $metal, $row, $col, [@vADJ]);
            $vertices{$vName} = [@vertex];
            $vIndex++;
        }
    }
}
$numVertices = keys %vertices;
print "a     # Vertices          = $numVertices\n";

### UNDIRECTED EDGE Generation
### UNDIRECTED EDGE Variables
my @udEdges = ();
my @udEdge = ();
my $udEdgeTerm1 = "";
my $udEdgeTerm2 = "";
my $udEdgeIndex = 0;
my $udEdgeNumber = -1;
my $vCost = 4;
my $mCost = 1;
my $wCost = 1;

### DATA STRUCTURE:  UNDIRECTED_EDGE [index] [Term1] [Term2] [mCost] [wCost]
for my $metal (0 .. $numMetalLayer-1) {     # Odd Layers: Vertical Direction   Even Layers: Bi-Direction
    for my $row (0 .. $numTrackH-1) {
        for my $col (0 .. $numTrackV-1) {
            $udEdgeTerm1 = "m".$metal."r".$row."c".$col;
			if ($metal == $numMetalLayer - 1){ # Top Layer (Horizontal, no up edge)
                if ($vertices{$udEdgeTerm1}[5][1] ne "null") { # Right Edge
					$udEdgeTerm2 = $vertices{$udEdgeTerm1}[5][1];
					@udEdge = ($udEdgeIndex, $udEdgeTerm1, $udEdgeTerm2, $mCost, $wCost);
					push (@udEdges, [@udEdge]);
					$udEdgeIndex++;
                }
			}
            elsif ($metal < $numMetalLayer-2 && $metal % 2 == 0) { # Even Layers except for the last layer ==> Horizontal/Vertical
                if ($vertices{$udEdgeTerm1}[5][1] ne "null") { # Right Edge
						$udEdgeTerm2 = $vertices{$udEdgeTerm1}[5][1];
						@udEdge = ($udEdgeIndex, $udEdgeTerm1, $udEdgeTerm2, $mCost, $wCost);
						push (@udEdges, [@udEdge]);
						$udEdgeIndex++;
                }
                if ($vertices{$udEdgeTerm1}[5][3] ne "null") { # Back Edge
                    $udEdgeTerm2 = $vertices{$udEdgeTerm1}[5][3];
					@udEdge = ($udEdgeIndex, $udEdgeTerm1, $udEdgeTerm2, $mCost, $wCost);
                    push (@udEdges, [@udEdge]);
                    $udEdgeIndex++;
                }
                if ($vertices{$udEdgeTerm1}[5][4] ne "null") { # Up Edge
					if(!($row == $h_track{int($metal/2)."_P"} || $row == $h_track{int($metal/2)."_N"})){
						$udEdgeTerm2 = $vertices{$udEdgeTerm1}[5][4];
						@udEdge = ($udEdgeIndex, $udEdgeTerm1, $udEdgeTerm2, $vCost, $vCost);
						push (@udEdges, [@udEdge]);
						$udEdgeIndex++;
					}
                }
            }
            else { # Odd Layers && last even layer ==> Vertical
                if ($vertices{$udEdgeTerm1}[5][3] ne "null") { # Back Edge
					$udEdgeTerm2 = $vertices{$udEdgeTerm1}[5][3];
					@udEdge = ($udEdgeIndex, $udEdgeTerm1, $udEdgeTerm2, $mCost, $wCost);
					push (@udEdges, [@udEdge]);
					$udEdgeIndex++;
                }
                if ($vertices{$udEdgeTerm1}[5][4] ne "null") { # Up Edge
					if(($metal == $numMetalLayer-2)||!($row == $h_track{int($metal/2)."_P"} || $row == $h_track{int($metal/2)."_N"})){
						$udEdgeTerm2 = $vertices{$udEdgeTerm1}[5][4];
						@udEdge = ($udEdgeIndex, $udEdgeTerm1, $udEdgeTerm2, $vCost, $vCost);
						push (@udEdges, [@udEdge]);
						$udEdgeIndex++;
					}
                }
            }
        }
    }
}
$udEdgeNumber = scalar @udEdges;
print "a     # udEdges           = $udEdgeNumber\n";

### BOUNDARY VERTICES Generation.
### DATA STRUCTURE:  Single Array includes all boundary vertices to L, R, F, B, U directions.
my @boundaryVertices = ();
my $numBoundaries = 0;

### Normal External Pins - (Top layer-1) only
for my $metal ($numMetalLayer-2 .. $numMetalLayer-2) { 
    for my $row (0 .. $numTrackH-1) {
        for my $col (0 .. $numTrackV-1) {
			if ($row == 0 || $row == $numTrackH-1) { next;}
			push (@boundaryVertices, "m".$metal."r".$row."c".$col);
        }
    }
}

$numBoundaries = scalar @boundaryVertices;
print "a     # Boundary Vertices = $numBoundaries\n";

my @boundaryVertices_vdd = ();
my $numBoundaries_vdd = 0;
my @boundaryVertices_vss = ();
my $numBoundaries_vss = 0;

for my $metal ($numMetalLayer-1 .. $numMetalLayer-1) { 
    for my $row (0 .. $numTrackH-1) {
		my $col = 0;
		if ($row == 0){
			push (@boundaryVertices_vdd, "m".$metal."r".$row."c".$col);
		}
		elsif ($row == $numTrackH-1) {
			push (@boundaryVertices_vss, "m".$metal."r".$row."c".$col);
		}
		else{
			next;
		}
    }
}

$numBoundaries_vdd = scalar @boundaryVertices_vdd;
print "a     # Boundary Vertices for VDD = $numBoundaries_vdd\n";
$numBoundaries_vss = scalar @boundaryVertices_vss;
print "a     # Boundary Vertices for VSS = $numBoundaries_vss\n";

my @outerPins = ();
my @outerPin = ();
my %h_outerPin = ();
my $numOuterPins = 0;
my $commodityInfo = -1;

for my $pinID (0 .. $#pins) {
    if ($pins[$pinID][4] eq "ext") {
        $commodityInfo = -1;  # Initializing
        # Find Commodity Infomation
        for my $netIndex (0 .. $#nets) {
            if ($nets[$netIndex][0] eq $pins[$pinID][1]){
                for my $sinkIndexofNet (0 .. $nets[$netIndex][4]){
                    if ( $nets[$netIndex][5][$sinkIndexofNet] eq $pins[$pinID][0]){
                        $commodityInfo = $sinkIndexofNet; 
                    }    
                }
            }
        }
        if ($commodityInfo == -1){
            print "ERROR: Cannot Find the commodity Information!!\n\n";
        }
        @outerPin = ($pins[$pinID][0],$pins[$pinID][1],$commodityInfo);
        push (@outerPins, [@outerPin]) ;
		$h_outerPin{$pins[$pinID][0]} = 1;
    }
}
$numOuterPins = scalar @outerPins;
print "a     # Outer Pins = $numOuterPins\n";

# Skip Corner Vertices => No Design Rule

### SOURCE and SINK Generation.  All sources and sinks are supernodes.
### DATA STRUCTURE:  SOURCE or SINK [netName] [#subNodes] [Arr. of sub-nodes, i.e., vertices]
my %sources = ();
my %sinks = ();
my @source = ();
my @sink = ();
my @subNodes = ();
my $numSubNodes = 0;
my $numSources = 0;
my $numSinks = 0;

my $outerPinFlagSink = 0;
my $outerPinFlagSink_vdd = 0;
my $outerPinFlagSink_vss = 0;
my $keyValue = "";

# Super Outer Node Keyword
my $keySON = "pinSON";
my $keySON_VDD = "pinSON_vdd";
my $keySON_VSS = "pinSON_vss";

for my $pinID (0 .. $#pins) {
    @subNodes = ();
	my %h_subNodes = ();
    if ($pins[$pinID][2] eq "s") { # source
        if ($pins[$pinID][4] eq "ext") {
			print "a        [SON Mode] Error! There exists an external source pin![$pins[$pinID][0]]\n";
			next;
        } else {
			my $instType = $inst[$h_inst_idx{$pins[$pinID][4]}][1] eq "PMOS"?"P":"N";
			if($pins[$pinID][5] eq "G"){
				for my $i(0 .. $numTier-1){
					if(!exists($h_subNodes{"m".(2*$i+1)."r".$h_track{$i."_".$instType}."c-1"})){
						push (@subNodes, "m".(2*$i+1)."r".$h_track{$i."_".$instType}."c-1");
						$h_subNodes{"m".(2*$i+1)."r".$h_track{$i."_".$instType}."c-1"} = 1;
					}
				}
			}
			else{
				for my $i(0 .. $numTier-1){
					if(!exists($h_subNodes{"m".(2*$i)."r".$h_track{$i."_".$instType}."c-1"})){
						push (@subNodes, "m".(2*$i)."r".$h_track{$i."_".$instType}."c-1");
					}
					if(!exists($h_subNodes{"m".(2*($i+1))."r".$h_track{$i."_".$instType}."c-1"})){
						push (@subNodes, "m".(2*($i+1))."r".$h_track{$i."_".$instType}."c-1");
					}
				}
			}
            $keyValue = $pins[$pinID][0];
        }
        $numSubNodes = scalar @subNodes;
        @source = ($pins[$pinID][1], $numSubNodes, [@subNodes]);
        # Outer Pin should be at last in the input File Format [2018-10-15]
        $sources{$keyValue} = [@source];
    }
    elsif ($pins[$pinID][2] eq "t") { # sink
        if ($pins[$pinID][4] eq "ext") {
			if($outerPinFlagSink == 0){
				if($pins[$pinID][5] ne "VDD" && $pins[$pinID][5] ne "VSS"){
					print "a        [SON Mode] Super Outer Node Simplifying - Sink\n";
					@subNodes = @boundaryVertices;
					$outerPinFlagSink = 1;
					$keyValue = $keySON;
					$numSubNodes = scalar @subNodes;
					@sink = ($pins[$pinID][1], $numSubNodes, [@subNodes]);
					$sinks{$keyValue} = [@sink];
				}
			}
			if($outerPinFlagSink_vdd == 0){
				if($pins[$pinID][5] eq "VDD"){
					print "a        [SON Mode] Super Node for VDD Connect - Sink\n";
					@subNodes = @boundaryVertices_vdd;
					$outerPinFlagSink_vdd= 1;
					$keyValue = $keySON_VDD;
					$numSubNodes = scalar @subNodes;
					@sink = ($pins[$pinID][1], $numSubNodes, [@subNodes]);
					$sinks{$keyValue} = [@sink];
				}
			}
			if($outerPinFlagSink_vss == 0){
				if($pins[$pinID][5] eq "VSS"){
					print "a        [SON Mode] Super Node for VSS Connect - Sink\n";
					@subNodes = @boundaryVertices_vss;
					$outerPinFlagSink_vss= 1;
					$keyValue = $keySON_VSS;
					$numSubNodes = scalar @subNodes;
					@sink = ($pins[$pinID][1], $numSubNodes, [@subNodes]);
					$sinks{$keyValue} = [@sink];
				}
			}
        } else {
			if($pins[$pinID][5] eq "G"){
				for my $i(0 .. $numTier-1){
					if(!exists($h_subNodes{"m".(2*$i+1)."r".$h_track{$i."_".$instType}."c-1"})){
						push (@subNodes, "m".(2*$i+1)."r".$h_track{$i."_".$instType}."c-1");
						$h_subNodes{"m".(2*$i+1)."r".$h_track{$i."_".$instType}."c-1"} = 1;
					}
				}
			}
			else{
				for my $i(0 .. $numTier-1){
					if(!exists($h_subNodes{"m".(2*$i)."r".$h_track{$i."_".$instType}."c-1"})){
						push (@subNodes, "m".(2*$i)."r".$h_track{$i."_".$instType}."c-1");
					}
					if(!exists($h_subNodes{"m".(2*($i+1))."r".$h_track{$i."_".$instType}."c-1"})){
						push (@subNodes, "m".(2*($i+1))."r".$h_track{$i."_".$instType}."c-1");
					}
				}
			}
            $keyValue = $pins[$pinID][0];
			$numSubNodes = scalar @subNodes;
			@sink = ($pins[$pinID][1], $numSubNodes, [@subNodes]);
			$sinks{$keyValue} = [@sink];
        }
    }
}
my $numExtNets = keys %h_extnets;
$numSources = keys %sources;
$numSinks = keys %sinks;
print "a     # Ext Nets          = $numExtNets\n";
print "a     # Sources           = $numSources\n";
print "a     # Sinks             = $numSinks\n";

############### Pin Information Modification #####################
for my $pinIndex (0 .. $#pins) {
	for my $outerPinIndex (0 .. $#outerPins){
		if ($pins[$pinIndex][0] eq $outerPins[$outerPinIndex][0] ){
			if($pins[$pinIndex][5] eq "VDD"){
				$pins[$pinIndex][0] = $keySON_VDD;
			}
			elsif($pins[$pinIndex][5] eq "VSS"){
				$pins[$pinIndex][0] = $keySON_VSS;
			}
			else{
				$pins[$pinIndex][0] = $keySON;
			}
			$pins[$pinIndex][1] = "Multi";
			next;
		}   
	}
}
############ SON Node should be last elements to use pop ###########
my $SONFlag = 0;
my $tmp_cnt = $#pins;
for(my $i=0; $i<=$tmp_cnt; $i++){
	if($pins[$tmp_cnt-$i][0] eq $keySON){
		$SONFlag = 1;
		@pin = pop @pins;
	}
}
if ($SONFlag == 1){
	push (@pins, @pin);
}
############### Net Information Modification from Outer pin to "SON"
for my $netIndex (0 .. $#nets) {
	for my $sinkIndex (0 .. $nets[$netIndex][4]-1){
		for my $outerPinIndex (0 .. $#outerPins){
			if ($nets[$netIndex][5][$sinkIndex] eq $outerPins[$outerPinIndex][0] ){
				if($h_pinName_type{$nets[$netIndex][5][$sinkIndex]} eq "VDD"){
					$nets[$netIndex][5][$sinkIndex] = $keySON_VDD;
				}
				elsif($h_pinName_type{$nets[$netIndex][5][$sinkIndex]} eq "VSS"){
					$nets[$netIndex][5][$sinkIndex] = $keySON_VSS;
				}
				else{
					$nets[$netIndex][5][$sinkIndex] = $keySON;
				}
				next;
			}
		}
	}
	for my $pinIndex (0 .. $nets[$netIndex][2]-1){
		for my $outerPinIndex (0 .. $#outerPins){
			if ($nets[$netIndex][6][$pinIndex] eq $outerPins[$outerPinIndex][0] ){
				if($h_pinName_type{$nets[$netIndex][6][$pinIndex]} eq "VDD"){
					$nets[$netIndex][6][$pinIndex] = $keySON_VDD;
				}
				elsif($h_pinName_type{$nets[$netIndex][6][$pinIndex]} eq "VSS"){
					$nets[$netIndex][6][$pinIndex] = $keySON_VSS;
				}
				else{
					$nets[$netIndex][6][$pinIndex] = $keySON;
				}
				next;
			}
		}
	}
}

### VIRTUAL EDGE Generation
### All supernodes are having names starting with 'pin'.
### DATA STRUCTURE:  VIRTUAL_EDGE [index] [Origin] [Destination] [Cost=0]
my @virtualEdges = ();
my @virtualEdge = ();
my $vEdgeIndex = 0;
my $vEdgeNumber = 0;
my $virtualCost = 0;

for my $pinID (0 .. $#pins) {
	my %h_vEdge = ();
    if ($pins[$pinID][2] eq "s") { # source
        if(exists $sources{$pins[$pinID][0]}){
			if(exists($h_inst_idx{$pins[$pinID][4]})){
				my $instIdx = $h_inst_idx{$pins[$pinID][4]};
				my $instWidth = $inst[$instIdx][2];
				my $instType = $inst[$instIdx][1] eq "PMOS"?"P":"N";
				for my $col (0 .. $numTrackV-1){
					if($pins[$pinID][5] eq "G"){
						for my $i(0 .. $numTier-1){
							if(!exists($h_vEdge{"m".(2*$i+1)."r".$h_track{$i."_".$instType}."c".$col})){
								@virtualEdge = ($vEdgeIndex, "m".(2*$i+1)."r".$h_track{$i."_".$instType}."c".$col, $pins[$pinID][0], $virtualCost);
								push (@virtualEdges, [@virtualEdge]);
								$vEdgeIndex++;
								$h_vEdge{"m".(2*$i+1)."r".$h_track{$i."_".$instType}."c".$col} = 1;
							}
						}
					}
					else{
						for my $i(0 .. $numTier-1){
							if(!exists($h_vEdge{"m".(2*$i)."r".$h_track{$i."_".$instType}."c".$col})){
								@virtualEdge = ($vEdgeIndex, "m".(2*$i)."r".$h_track{$i."_".$instType}."c".$col, $pins[$pinID][0], $virtualCost);
								push (@virtualEdges, [@virtualEdge]);
								$vEdgeIndex++;
								$h_vEdge{"m".(2*$i)."r".$h_track{$i."_".$instType}."c".$col} = 1;
							}
							if(!exists($h_vEdge{"m".(2*($i+1))."r".$h_track{$i."_".$instType}."c".$col})){
								@virtualEdge = ($vEdgeIndex, "m".(2*($i+1))."r".$h_track{$i."_".$instType}."c".$col, $pins[$pinID][0], $virtualCost);
								push (@virtualEdges, [@virtualEdge]);
								$vEdgeIndex++;
								$h_vEdge{"m".(2*($i+1))."r".$h_track{$i."_".$instType}."c".$col} = 1;
							}
						}
					}
				}
			}
			else{
				print "[ERROR] Virtual Edge Generation : Instance Information not found!!\n";
				exit(-1);
			}
        }
    }
    elsif ($pins[$pinID][2] eq "t") { # sink
        if(exists $sinks{$pins[$pinID][0]}){
			if($pins[$pinID][0] eq $keySON || $pins[$pinID][0] eq $keySON_VDD || $pins[$pinID][0] eq $keySON_VSS){
			   for my $term (0 ..  $sinks{$pins[$pinID][0]}[1]-1){
					@virtualEdge = ($vEdgeIndex, $sinks{$pins[$pinID][0]}[2][$term], $pins[$pinID][0], $virtualCost);
					push (@virtualEdges, [@virtualEdge]);
					$vEdgeIndex++;
				}
			}
			elsif(exists($h_inst_idx{$pins[$pinID][4]})){
				my $instIdx = $h_inst_idx{$pins[$pinID][4]};
				my $instWidth = $inst[$instIdx][2];
				my $instType = $inst[$instIdx][1] eq "PMOS"?"P":"N";
				for my $col (0 .. $numTrackV-1){
					if($pins[$pinID][5] eq "G"){
						for my $i(0 .. $numTier-1){
							if(!exists($h_vEdge{"m".(2*$i+1)."r".$h_track{$i."_".$instType}."c".$col})){
								@virtualEdge = ($vEdgeIndex, "m".(2*$i+1)."r".$h_track{$i."_".$instType}."c".$col, $pins[$pinID][0], $virtualCost);
								push (@virtualEdges, [@virtualEdge]);
								$vEdgeIndex++;
								$h_vEdge{"m".(2*$i+1)."r".$h_track{$i."_".$instType}."c".$col} = 1;
							}
						}
					}
					else{
						for my $i(0 .. $numTier-1){
							if(!exists($h_vEdge{"m".(2*$i)."r".$h_track{$i."_".$instType}."c".$col})){
								@virtualEdge = ($vEdgeIndex, "m".(2*$i)."r".$h_track{$i."_".$instType}."c".$col, $pins[$pinID][0], $virtualCost);
								push (@virtualEdges, [@virtualEdge]);
								$vEdgeIndex++;
								$h_vEdge{"m".(2*$i)."r".$h_track{$i."_".$instType}."c".$col} = 1;
							}
							if(!exists($h_vEdge{"m".(2*($i+1))."r".$h_track{$i."_".$instType}."c".$col})){
								@virtualEdge = ($vEdgeIndex, "m".(2*($i+1))."r".$h_track{$i."_".$instType}."c".$col, $pins[$pinID][0], $virtualCost);
								push (@virtualEdges, [@virtualEdge]);
								$vEdgeIndex++;
								$h_vEdge{"m".(2*($i+1))."r".$h_track{$i."_".$instType}."c".$col} = 1;
							}
						}
					}
				}

			}
			else{
				print "[ERROR] Virtual Edge Generation : Instance Information not found!!\n";
				exit(-1);
			}
        }
    }
}
my %edge_in = ();
my %edge_out = ();
for my $edge (0 .. @udEdges-1){
	push @{ $edge_out{$udEdges[$edge][1]} }, $edge;
	push @{ $edge_in{$udEdges[$edge][2]} }, $edge;
}
my %vedge_in = ();
my %vedge_out = ();
for my $edge (0 .. @virtualEdges-1){
	push @{ $vedge_out{$virtualEdges[$edge][1]} }, $edge;
	push @{ $vedge_in{$virtualEdges[$edge][2]} }, $edge;
}
$vEdgeNumber = scalar @virtualEdges;
print "a     # Virtual Edges     = $vEdgeNumber\n";
### END:  DATA STRUCTURE ##############################################################################################
open (my $out, '>', $outfile);
print "a   Generating SMT-LIB 2.0 Standard Input Code.\n";

### INIT
print $out ";Formulation for SMT\n";
print $out ";	Format: SMT-LIB 2.0\n";
print $out ";	Version: 1.0\n";
print $out ";   Authors:     Daeyeal Lee, Chung-Kuan Cheng\n";
print $out ";   DO NOT DISTRIBUTE IN ANY PURPOSE! \n\n";
print $out ";	Input File:  $workdir/$infile\n";
print $out ";   Design Parameters : [NumTier = $numTier]\n";
print $out ";                     : [NumHTrack = $numHTrack, Track for 1 Tier PFET = $trackPFET, Track for 1 Tier NFET = $trackNFET], MPO=$MPO_Parameter\n";
print $out ";                     : [BS = ".($BS==0?"Disabled":"Enabled").", CP = ".($CP==0?"Disabled":"Enabled").", LC = ".($LC==0?"Disabled":"Enabled(T=$LT)")."]\n\n";

print $out ";Layout Information\n";
print $out ";	Placement & Routing\n";
print $out ";	# Vertical Tracks   = $numTrackV\n";
print $out ";	# Horizontal Tracks = $numTrackH\n";
print $out ";	# Instances         = $numInstance\n";
print $out ";	# Nets              = $totalNets\n";
print $out ";	# Pins              = $totalPins\n";
print $out ";	# Sources           = $numSources\n";
print $out ";	List of Sources   = ";
foreach my $key (sort(keys %sources)) {
    print $out "$key ";
}
print $out "\n";
print $out ";	# Sinks             = $numSinks\n";
print $out ";	List of Sinks     = ";
foreach my $key (sort(keys %sinks)) {
    print $out "$key ";
}
print $out "\n";
print $out ";	# Outer Pins        = $numOuterPins\n";
print $out ";	List of Outer Pins= ";
for my $i (0 .. $#outerPins) {              # All SON (Super Outer Node)
    print $out "$outerPins[$i][0] ";        # 0 : Pin number , 1 : net number
}
print $out "\n";
print $out ";	Outer Pins Information= ";
for my $i (0 .. $#outerPins) {              # All SON (Super Outer Node)
    print $out " $outerPins[$i][1]=$outerPins[$i][2] ";        # 0 : Net number , 1 : Commodity number
}
print $out "\n";
print $out "\n\n";

### Z3 Option Set ###
my $lenV = length(sprintf("%b", $numTrackV))+1;
my $lenH = length(sprintf("%b", $numTrackH))+1;
my $lenT = length(sprintf("%b", $numTier*$numInstance));
my $lenN = length(sprintf("%b", $numOuterPins*$numTrackV));
my $lenR = length(sprintf("%b", $numOuterPins*$numTrackH));
print $out ";(set-option :produce-unsat-cores true)\n";
print $out ";Begin SMT Formulation\n\n";

print $out "(declare-const COST_SIZE (_ BitVec $lenV))\n";
print $out "(declare-const COST_SIZE_P (_ BitVec $lenV))\n";
print $out "(declare-const COST_SIZE_N (_ BitVec $lenV))\n";
for my $i (0 .. $numTrackH-1){
	print $out "(declare-const LM_TRACK_$i Bool)\n";
}
foreach my $key(sort(keys %h_extnets)){
	for my $i (0 .. $numTrackH-1){
		print $out "(declare-const N".$key."_LM_TRACK_$i Bool)\n";
	}
	print $out "(declare-const N".$key."_LM_TRACK Bool)\n";
}
foreach my $key1(sort(keys %h_extnets)){
	for my $i (0 .. $numTrackV-1){
		print $out "(declare-const N".$key1."_C$i (_ BitVec $lenN))\n";
		print $out "(declare-const N".$key1."_C$i\_EN Bool)\n";
	}
	for my $i (1 .. $numTrackH-2){
		print $out "(declare-const N".$key1."_R$i (_ BitVec $lenR))\n";
		print $out "(declare-const N".$key1."_R$i\_EN Bool)\n";
	}
}

### Placement ###
print "a   A. Variables for Placement\n";
print $out ";A. Variables for Placement\n";
print $out "(define-fun max ((x (_ BitVec $lenV)) (y (_ BitVec $lenV))) (_ BitVec $lenV)\n";
print $out "  (ite (bvugt x y) x y)\n";
print $out ")\n";

for my $i (0 .. $numInstance - 1) {
	print $out "(declare-const x$i (_ BitVec $lenV))\n";     # instance x position
	print $out "(declare-const y$i (_ BitVec $lenH))\n";     # instance y position
	print $out "(declare-const t$i (_ BitVec $lenT))\n";     # Instance Tier Location
}

print $out "(declare-const trackH (_ BitVec $lenH))\n";	    # track height
print $out "(declare-const trackPFET (_ BitVec $lenH))\n";	    # track location of Tier 1 PFET
print $out "(declare-const trackNFET (_ BitVec $lenH))\n";	    # track location of Tier 1 NFET
print $out "(declare-const numTier (_ BitVec $lenT))\n";	    # number of Tier

print $out "(assert (= trackH (_ bv$numTrackH $lenH)))\n";
print $out "(assert (= trackPFET (_ bv$trackPFET $lenH)))\n";
print $out "(assert (= trackNFET (_ bv$trackNFET $lenH)))\n";
print $out "(assert (= numTier (_ bv$numTier $lenT)))\n";

my $minWidth = 0;
if($lastIdxPMOS + 1 > $numInstance - $lastIdxPMOS - 1){
	$minWidth = int(($lastIdxPMOS+1)/$numTier+0.999);
}
else{
	$minWidth = int(($numInstance-$lastIdxPMOS-1)/$numTier+0.999);
}
print $out "(assert (bvuge COST_SIZE (_ bv".($minWidth-1)." $lenV)))\n";
print $out "(assert (bvule COST_SIZE (_ bv".($numTrackV-1)." $lenV)))\n";
print $out "(assert (bvule COST_SIZE_P (_ bv".($numTrackV-1)." $lenV)))\n";
print $out "(assert (bvule COST_SIZE_N (_ bv".($numTrackV-1)." $lenV)))\n";

print "a   B. Constraints for Placement\n";
print $out "\n";
print $out ";B. Constraints for Placement\n";

for my $i (0 .. $numInstance - 1) {
	print $out "(assert (and (bvuge x$i (_ bv0 $lenV)) (bvule x$i (_ bv".($numTrackV - 1)." $lenV))))\n";
	print $out "(assert (and (bvuge t$i (_ bv0 $lenT)) (bvule t$i (_ bv".($numTier - 1)." $lenT))))\n";
}
for my $i (0 .. $lastIdxPMOS) {
	print $out "(assert (= y$i (_ bv$trackPFET $lenH)))\n";
}
for my $i ($lastIdxPMOS + 1 .. $numInstance - 1) {
	print $out "(assert (= y$i (_ bv$trackNFET $lenH)))\n";
}
# Relative Positioning Constraint
for my $i (0 .. $lastIdxPMOS) {
	for my $j (0 .. $lastIdxPMOS) {
		if ($i != $j) {
			my $s_i = $h_instIdx_S{$i};
			my $d_i = $h_instIdx_D{$i};
			my $s_j = $h_instIdx_S{$j};
			my $d_j = $h_instIdx_D{$j};
			my $n_s_i = $h_netName_idx{$pins[$h_pinId_idx{$s_i}][1]};
			my $n_d_i = $h_netName_idx{$pins[$h_pinId_idx{$d_i}][1]};
			my $n_s_j = $h_netName_idx{$pins[$h_pinId_idx{$s_j}][1]};
			my $n_d_j = $h_netName_idx{$pins[$h_pinId_idx{$d_j}][1]};

			if(($n_s_i != $n_s_j) && ($n_s_i != $n_d_j) && ($n_d_i != $n_s_j) && ($n_d_i != $n_d_j)){
				print $out "(assert (ite (= x$i x$j) (ite (bvult t$i t$j) (bvult (bvadd t$i (_ bv1 $lenT)) t$j) (bvult (bvadd t$j (_ bv1 $lenT)) t$i)) (= true true)))\n";
			}
			else{
				print $out "(assert (ite (= x$i x$j) (ite (bvult t$i t$j) (bvult t$i t$j) (bvult t$j t$i)) (= true true)))\n";
			}
			print $out ";(assert (ite (= t$i t$j) (or (bvult x$i x$j) (bvugt x$i x$j)) (= true true)))\n";
			print $out "(assert (ite (= t$i t$j) (ite (bvult x$i x$j) (bvult x$i x$j) (ite (bvugt x$i x$j) (bvugt x$i x$j) (= true false))) (= true true)))\n";
		}
	}
}
for my $i ($lastIdxPMOS + 1 .. $numInstance - 1) {
	for my $j ($lastIdxPMOS + 1 .. $numInstance - 1) {
		if ($i != $j) {
			my $s_i = $h_instIdx_S{$i};
			my $d_i = $h_instIdx_D{$i};
			my $s_j = $h_instIdx_S{$j};
			my $d_j = $h_instIdx_D{$j};
			my $n_s_i = $h_netName_idx{$pins[$h_pinId_idx{$s_i}][1]};
			my $n_d_i = $h_netName_idx{$pins[$h_pinId_idx{$d_i}][1]};
			my $n_s_j = $h_netName_idx{$pins[$h_pinId_idx{$s_j}][1]};
			my $n_d_j = $h_netName_idx{$pins[$h_pinId_idx{$d_j}][1]};

			if(($n_s_i != $n_s_j) && ($n_s_i != $n_d_j) && ($n_d_i != $n_s_j) && ($n_d_i != $n_d_j)){
				print $out "(assert (ite (= x$i x$j) (ite (bvult t$i t$j) (bvult (bvadd t$i (_ bv1 $lenT)) t$j) (bvult (bvadd t$j (_ bv1 $lenT)) t$i)) (= true true)))\n";
			}
			else{
				print $out "(assert (ite (= x$i x$j) (ite (bvult t$i t$j) (bvult t$i t$j) (bvult t$j t$i)) (= true true)))\n";
			}
			print $out ";(assert (ite (= t$i t$j) (or (bvult x$i x$j) (bvugt x$i x$j)) (= true true)))\n";
			print $out "(assert (ite (= t$i t$j) (ite (bvult x$i x$j) (bvult x$i x$j) (ite (bvugt x$i x$j) (bvugt x$i x$j) (= true false))) (= true true)))\n";
		}
	}
}

print "a   C. Variables for Routing\n";
print $out "\n";
print $out ";C. Variables for Routing\n";

### Metal binary variables
for my $udeIndex (0 .. $#udEdges) {
    print $out "(declare-const M_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] Bool)\n";
}
for my $vEdgeIndex (0 .. $#virtualEdges) {
    print $out "(declare-const M_$virtualEdges[$vEdgeIndex][1]_$virtualEdges[$vEdgeIndex][2] Bool)\n";
}
### Edge binary variables
for my $netIndex (0 .. $#nets) {
    for my $udeIndex (0 .. $#udEdges) {
        print $out "(declare-const N$nets[$netIndex][1]_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] Bool)\n";
    }
    ### VIRTUAL_EDGE [index] [Origin] [Destination] [Cost=0]
    for my $vEdgeIndex (0 .. $#virtualEdges) {
		my $isInNet = 0;
        if ($virtualEdges[$vEdgeIndex][2] =~ /^pin/) { # source
			if($virtualEdges[$vEdgeIndex][2] eq $nets[$netIndex][3]){
				$isInNet = 1;
			}
			if($isInNet == 1){
				print $out "(declare-const N$nets[$netIndex][1]_E_$virtualEdges[$vEdgeIndex][1]_$virtualEdges[$vEdgeIndex][2] Bool)\n";
			}
			$isInNet = 0;
			for my $i (0 .. $nets[$netIndex][4]-1){
				if($virtualEdges[$vEdgeIndex][2] eq $nets[$netIndex][5][$i]){
					$isInNet = 1;
				}
			}
			if($isInNet == 1){
				print $out "(declare-const N$nets[$netIndex][1]_E_$virtualEdges[$vEdgeIndex][1]_$virtualEdges[$vEdgeIndex][2] Bool)\n";
			}
        }
    }
}
### Commodity Flow binary variables
for my $netIndex (0 .. $#nets) {
    for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
        for my $udEdgeIndex (0 .. $#udEdges) {
            print $out "(declare-const N$nets[$netIndex][1]_C$commodityIndex\_E_$udEdges[$udEdgeIndex][1]_$udEdges[$udEdgeIndex][2] Bool)\n";
        }
    }
    ### VIRTUAL_EDGE [index] [Origin] [Destination] [Cost=0]
    for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
		for my $vEdgeIndex (0 .. $#virtualEdges) {
			my $isInNet = 0;
			if ($virtualEdges[$vEdgeIndex][2] =~ /^pin/) { # source
				if($virtualEdges[$vEdgeIndex][2] eq $nets[$netIndex][3]){
					$isInNet = 1;
				}
				if($isInNet == 1){
					print $out "(declare-const N$nets[$netIndex][1]_C$commodityIndex\_E_$virtualEdges[$vEdgeIndex][1]_$virtualEdges[$vEdgeIndex][2] Bool)\n";
				}
				$isInNet = 0;
				if($virtualEdges[$vEdgeIndex][2] eq $nets[$netIndex][5][$commodityIndex]){
					$isInNet = 1;
				}
				if($isInNet == 1){
					print $out "(declare-const N$nets[$netIndex][1]_C$commodityIndex\_E_$virtualEdges[$vEdgeIndex][1]_$virtualEdges[$vEdgeIndex][2] Bool)\n";
				}
			}
		}
	}
}


print "a   D. Constraints for Routing\n";
print $out "\n";
print $out ";D. Constraints for Routing\n";

for my $row (0 .. $numTrackH -1){
	if($row == 0 || $row == $numTrackH-1) { 
		print $out "(assert (= LM_TRACK_$row false))\n";
		next;
	}
	print $out "(assert (= LM_TRACK_$row (or";
	for my $udeIndex (0 .. $#udEdges) {
		my $fromMetal = (split /[a-z]/, $udEdges[$udeIndex][1])[1]; # 1:metal 2:row 3:col
		my $toMetal = (split /[a-z]/, $udEdges[$udeIndex][2])[1]; # 1:metal 2:row 3:col
		my $fromCol = (split /[a-z]/, $udEdges[$udeIndex][1])[3]; # 1:metal 2:row 3:col
		my $toCol = (split /[a-z]/, $udEdges[$udeIndex][2])[3]; # 1:metal 2:row 3:col
		my $fromRow = (split /[a-z]/, $udEdges[$udeIndex][1])[2]; # 1:metal 2:row 3:col
		my $toRow = (split /[a-z]/, $udEdges[$udeIndex][2])[2]; # 1:metal 2:row 3:col
		if($toMetal == $numMetalLayer-1 && ($fromRow == $row && $toRow == $row)){
			print $out " M_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2]";
		}
	}
	print $out ")))\n";
}
foreach my $key(sort(keys %h_extnets)){
	my $netIndex = $h_idx{$key};
	for my $row (0 .. $numTrackH -1){
		if($row == 0 || $row == $numTrackH-1) {
			print $out "(assert (= N".$key."_LM_TRACK_$row false))\n";
			next;
		}
		my $tmp_str = "";
		my $cnt_var = 0;
		$tmp_str.="(assert (= N".$key."_LM_TRACK_$row (or";
		for my $udeIndex (0 .. $#udEdges) {
			my $fromMetal = (split /[a-z]/, $udEdges[$udeIndex][1])[1]; # 1:metal 2:row 3:col
			my $toMetal = (split /[a-z]/, $udEdges[$udeIndex][2])[1]; # 1:metal 2:row 3:col
			my $fromCol = (split /[a-z]/, $udEdges[$udeIndex][1])[3]; # 1:metal 2:row 3:col
			my $toCol = (split /[a-z]/, $udEdges[$udeIndex][2])[3]; # 1:metal 2:row 3:col
			my $fromRow = (split /[a-z]/, $udEdges[$udeIndex][1])[2]; # 1:metal 2:row 3:col
			my $toRow = (split /[a-z]/, $udEdges[$udeIndex][2])[2]; # 1:metal 2:row 3:col
			if($toMetal == $numMetalLayer-1 && ($fromRow == $row && $toRow == $row)){
				for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
					$tmp_str.=" N$key\_C$commodityIndex\_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2]";
					$cnt_var++;
				}
			}
		}
		$tmp_str.=")))\n";
		if($cnt_var==0){
			$tmp_str="(assert (= N".$key."_LM_TRACK_$row false))\n";
		}
		print $out $tmp_str;
	}
	print $out "(assert (= N".$key."_LM_TRACK (or";
	for my $row (0 .. $numTrackH -1){
		print $out " N".$key."_LM_TRACK_$row";
	}
	print $out ")))\n";
}

### Flow Capacity Control
print $out ";Flow Capacity Control\n";
for my $netIndex (0 .. $#nets) {
	for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
		my $instIdx = 0;
		my $instType = "";
		my @tmp_vname = ();
		my $vName = "";

		## Source MaxFlow Indicator
		$instIdx = $h_inst_idx{$pins[$h_pinId_idx{$nets[$netIndex][3]}][4]};
		$instType = $inst[$instIdx][1] eq "PMOS"?"P":"N";

		for my $col (0 .. $numTrackV-1){
			@tmp_vname = ();
			$vName = "";
			if($pins[$h_pinId_idx{$nets[$netIndex][3]}][5] eq "G"){ ### GATE Pin
				for my $i(0 .. $numTier-1){
					$vName = "m".(2*$i+1)."r".$h_track{$i."_".$instType}."c".$col;
					push(@tmp_vname, "N$nets[$netIndex][1]_C$commodityIndex\_E_$vName\_$nets[$netIndex][3]");
				}
				if($numTier == 1){
					print $out "(assert (ite (= x$instIdx (_ bv$col $lenV)) (= $tmp_vname[0] true) (= $tmp_vname[0] false)))\n";
				}
				else{
					print $out "(assert (ite (= x$instIdx (_ bv$col $lenV)) ";
					for my $i(0 .. $numTier-1){
						print $out "(ite (= t$instIdx (_ bv$i $lenT)) (and (= $tmp_vname[$i] true)";
						for my $j(0 .. $numTier-1){
							if($i == $j) { next;}
							print $out " (= $tmp_vname[$j] false)";
						}
						print $out ") ";
					}
					print $out "(= true false)";
					for my $i(0 .. $numTier-1){
						print $out ")";
					}
					print $out " (and";
					for my $i(0 .. $numTier-1){
						print $out " (= $tmp_vname[$i] false)";
					}
					print $out ")))\n";
				}
			}
			else{	### Source/Drain Pins
				for my $i(0 .. $numTier){
					if($i == $numTier){
						$vName = "m".(2*$i)."r".$h_track{($i-1)."_".$instType}."c".$col;
					}
					else{
						$vName = "m".(2*$i)."r".$h_track{$i."_".$instType}."c".$col;
					}
					push(@tmp_vname, "N$nets[$netIndex][1]_C$commodityIndex\_E_$vName\_$nets[$netIndex][3]");
				}
				if($numTier == 1){
					print $out "(assert (ite (= x$instIdx (_ bv$col $lenV)) (and ((_ at-least 1) $tmp_vname[0] $tmp_vname[1]) ((_ at-most 1) $tmp_vname[0] $tmp_vname[1]))";
					print $out " (and (= $tmp_vname[0] false) (= $tmp_vname[1] false))))\n";
				}
				else{
					print $out "(assert (ite (= x$instIdx (_ bv$col $lenV)) ";
					for my $i(0 .. $numTier-1){
						print $out "(ite (= t$instIdx (_ bv$i $lenT)) (and ((_ at-least 1) $tmp_vname[$i] $tmp_vname[$i+1]) ((_ at-most 1) $tmp_vname[$i] $tmp_vname[$i+1])";
						for my $j(0 .. $numTier){
							if($i == $j || ($i + 1) == $j) { next;}
							print $out " (= $tmp_vname[$j] false)";
						}
						print $out ") ";
					}
					print $out "(= true false)";
					for my $i(0 .. $numTier-1){
						print $out ")";
					}
					print $out " (and";
					for my $i(0 .. $numTier){
						print $out " (= $tmp_vname[$i] false)";
					}
					print $out ")))\n";
				}
			}
		}
		## Sink MaxFlow Indicator
		if($nets[$netIndex][5][$commodityIndex] eq $keySON || $nets[$netIndex][5][$commodityIndex] eq $keySON_VDD || $nets[$netIndex][5][$commodityIndex] eq $keySON_VSS){
			next;
		}
		$instIdx = $h_inst_idx{$pins[$h_pinId_idx{$nets[$netIndex][5][$commodityIndex]}][4]};
		$instType = $inst[$instIdx][1] eq "PMOS"?"P":"N";
		for my $col (0 .. $numTrackV-1){
			@tmp_vname = ();
			$vName = "";
			if($pins[$h_pinId_idx{$nets[$netIndex][5][$commodityIndex]}][5] eq "G"){ ### GATE Pin
				for my $i(0 .. $numTier-1){
					$vName = "m".(2*$i+1)."r".$h_track{$i."_".$instType}."c".$col;
					push(@tmp_vname, "N$nets[$netIndex][1]_C$commodityIndex\_E_$vName\_$nets[$netIndex][5][$commodityIndex]");
				}
				if($numTier == 1){
					print $out "(assert (ite (= x$instIdx (_ bv$col $lenV)) (= $tmp_vname[0] true) (= $tmp_vname[0] false)))\n";
				}
				else{
					print $out "(assert (ite (= x$instIdx (_ bv$col $lenV)) ";
					for my $i(0 .. $numTier-1){
						print $out "(ite (= t$instIdx (_ bv$i $lenT)) (and (= $tmp_vname[$i] true)";
						for my $j(0 .. $numTier-1){
							if($i == $j) { next;}
							print $out " (= $tmp_vname[$j] false)";
						}
						print $out ") ";
					}
					print $out "(= true false)";
					for my $i(0 .. $numTier-1){
						print $out ")";
					}
					print $out " (and";
					for my $i(0 .. $numTier-1){
						print $out " (= $tmp_vname[$i] false)";
					}
					print $out ")))\n";
				}
			}
			else{	### Source/Drain Pins
				for my $i(0 .. $numTier){
					if($i == $numTier){
						$vName = "m".(2*$i)."r".$h_track{($i-1)."_".$instType}."c".$col;
					}
					else{
						$vName = "m".(2*$i)."r".$h_track{$i."_".$instType}."c".$col;
					}
					push(@tmp_vname, "N$nets[$netIndex][1]_C$commodityIndex\_E_$vName\_$nets[$netIndex][5][$commodityIndex]");
				}
				if($numTier == 1){
					print $out "(assert (ite (= x$instIdx (_ bv$col $lenV)) (and ((_ at-least 1) $tmp_vname[0] $tmp_vname[1]) ((_ at-most 1) $tmp_vname[0] $tmp_vname[1]))";
					print $out " (and (= $tmp_vname[0] false) (= $tmp_vname[1] false))))\n";
				}
				else{
					print $out "(assert (ite (= x$instIdx (_ bv$col $lenV)) ";
					for my $i(0 .. $numTier-1){
						print $out "(ite (= t$instIdx (_ bv$i $lenT)) (and ((_ at-least 1) $tmp_vname[$i] $tmp_vname[$i+1]) ((_ at-most 1) $tmp_vname[$i] $tmp_vname[$i+1])";
						for my $j(0 .. $numTier){
							if($i == $j || ($i + 1) == $j) { next;}
							print $out " (= $tmp_vname[$j] false)";
						}
						print $out ") ";
					}
					print $out "(= true false)";
					for my $i(0 .. $numTier-1){
						print $out ")";
					}
					print $out " (and";
					for my $i(0 .. $numTier){
						print $out " (= $tmp_vname[$i] false)";
					}
					print $out ")))\n";
				}
			}
		}
	}
}
### COMMODITY FLOW Conservation
print "a     1. Commodity flow conservation ";
print $out ";1. Commodity flow conservation for each vertex and every connected edge to the vertex\n";
for my $netIndex (0 .. $#nets) {
	for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
		for my $metal (0 .. $numMetalLayer-1) {   
			for my $row (0 .. $numTrackH-1) {
				for my $col (0 .. $numTrackV-1) {
					$vName = "m".$metal."r".$row."c".$col;
					my $tmp_str = "";
					my @tmp_var = ();
					my $cnt_var = 0;
					for my $i (0 .. $#{$edge_in{$vName}}){ # incoming
						$tmp_str ="N$nets[$netIndex][1]\_";
						$tmp_str.="C$commodityIndex\_";
						$tmp_str.="E_$udEdges[$edge_in{$vName}[$i]][1]_$vName";
						push(@tmp_var, $tmp_str);
						$cnt_var++;
					}
					for my $i (0 .. $#{$edge_out{$vName}}){ # incoming
						$tmp_str ="N$nets[$netIndex][1]\_";
						$tmp_str.="C$commodityIndex\_";
						$tmp_str.="E_$vName\_$udEdges[$edge_out{$vName}[$i]][2]";
						push(@tmp_var, $tmp_str);
						$cnt_var++;
					}
					for my $i (0 .. $#{$vedge_out{$vName}}){ # sink
						if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][3]){
							$tmp_str ="N$nets[$netIndex][1]\_";
							$tmp_str.="C$commodityIndex\_";
							$tmp_str.="E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
							push(@tmp_var, $tmp_str);
							$cnt_var++;
						}
						if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][5][$commodityIndex]){
							$tmp_str ="N$nets[$netIndex][1]\_";
							$tmp_str.="C$commodityIndex\_";
							$tmp_str.="E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
							push(@tmp_var, $tmp_str);
							$cnt_var++;
						}
					}
					# if # of rest variables is one, then that variable should be false
					if($cnt_var == 1){
						print $out "(assert (= $tmp_var[0] false))\n";
					}
					elsif($cnt_var == 2){
						print $out "(assert (= (or (not $tmp_var[0]) $tmp_var[1]) true))\n";
						print $out "(assert (= (or $tmp_var[0] (not $tmp_var[1])) true))\n";
					}
					elsif($cnt_var > 2){
						#at-most 2
						print $out "(assert ((_ at-most 2)";
						for my $i(0 .. $#tmp_var){
							print $out  " $tmp_var[$i]";
						}
						print $out "))\n";
						# not exactly-1
						for my $i(0 .. $#tmp_var){
							print $out "(assert (= (or";
							for my $j(0 .. $#tmp_var){
									if($i==$j){
										print $out " (not $tmp_var[$j])";
									}
									else{
										print $out " $tmp_var[$j]";
									}
							}
							print $out ") true))\n";
						}
					}
				}
			}
		}
	}
}
### Net Variables for CFC
for my $netIndex (0 .. $#nets) {
	for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
		for my $pinIndex (0 .. $#pins) {
			$vName = $pins[$pinIndex][0];
			if($vName eq $nets[$netIndex][5][$commodityIndex]){
				if($vName eq $keySON || $vName eq $keySON_VDD || $vName eq $keySON_VSS){
					my $tmp_str = "";
					my @tmp_var = ();
					my $cnt_var = 0;
					for my $i (0 .. $#{$vedge_in{$vName}}){ # sink
						my $metal = (split /[a-z]/, $virtualEdges[$vedge_in{$vName}[$i]][1])[1]; # 1:metal 2:row 3:col
						my $row = (split /[a-z]/, $virtualEdges[$vedge_in{$vName}[$i]][1])[2]; # 1:metal 2:row 3:col
						$tmp_str ="N$nets[$netIndex][1]\_";
						$tmp_str.="C$commodityIndex\_";
						$tmp_str.="E_$virtualEdges[$vedge_in{$vName}[$i]][1]_$vName";
						push(@tmp_var, $tmp_str);
						$cnt_var++;
					}
					if($cnt_var == 1){
						print $out "(assert (= $tmp_var[0] true))\n";
					}
					elsif($cnt_var > 0){
						#at-most 1
						print $out "(assert ((_ at-most 1)";
						for my $i(0 .. $#tmp_var){
							print $out " $tmp_var[$i]";
						}
						print $out "))\n";
						#at-least 1
						print $out "(assert ((_ at-least 1)";
						for my $i(0 .. $#tmp_var){
							print $out " $tmp_var[$i]";
						}
						print $out "))\n";
					}
				}
				else{
					my $instIdx = 0;
					## Sink MaxFlow Indicator
					$instIdx = $h_inst_idx{$pins[$h_pinId_idx{$nets[$netIndex][5][$commodityIndex]}][4]};
					my @tmp_var = ();
					my $cnt_var = 0;
					for my $col (0 .. $numTrackV -1){
						my $tmp_str = "";
						print $out "(declare-const C_N$nets[$netIndex][1]\_C$commodityIndex\_c$col\_$vName Bool)\n";
						print $out "(assert (= C_N$nets[$netIndex][1]\_C$commodityIndex\_c$col\_$vName (or";
						for my $i (0 .. $#{$vedge_in{$vName}}){ # sink
							my $Col   = (split /[a-z]/, $virtualEdges[$vedge_in{$vName}[$i]][1])[3];
							$tmp_str ="N$nets[$netIndex][1]\_";
							$tmp_str.="C$commodityIndex\_";
							$tmp_str.="E_$virtualEdges[$vedge_in{$vName}[$i]][1]_$vName";
							if($Col == $col){
								print $out " $tmp_str";
							}
						}
						print $out ")))\n";
						push(@tmp_var, "C_N$nets[$netIndex][1]\_C$commodityIndex\_c$col\_$vName");
						$cnt_var++;
					}
					if($cnt_var == 1){
						print $out "(assert (= $tmp_var[0] true))\n";
					}
					elsif($cnt_var > 0){
						#at-most 1
						print $out "(assert ((_ at-most 1)";
						for my $i(0 .. $#tmp_var){
							print $out " $tmp_var[$i]";
						}
						print $out "))\n";
						#at-least 1
						print $out "(assert ((_ at-least 1)";
						for my $i(0 .. $#tmp_var){
							print $out " $tmp_var[$i]";
						}
						print $out "))\n";
					}
				}
			}
			if($vName eq $nets[$netIndex][3]){
				my $instIdx = 0;
				## Source MaxFlow Indicator
				$instIdx = $h_inst_idx{$pins[$h_pinId_idx{$nets[$netIndex][3]}][4]};
				my @tmp_var = ();
				my $cnt_var = 0;
				for my $col (0 .. $numTrackV -1){
					my $tmp_str = "";
					print $out "(declare-const C_N$nets[$netIndex][1]\_C$commodityIndex\_c$col\_$vName Bool)\n";
					print $out "(assert (= C_N$nets[$netIndex][1]\_C$commodityIndex\_c$col\_$vName (or";
					for my $i (0 .. $#{$vedge_in{$vName}}){ # sink
						my $Col   = (split /[a-z]/, $virtualEdges[$vedge_in{$vName}[$i]][1])[3];
						$tmp_str ="N$nets[$netIndex][1]\_";
						$tmp_str.="C$commodityIndex\_";
						$tmp_str.="E_$virtualEdges[$vedge_in{$vName}[$i]][1]_$vName";
						if($Col == $col){
							print $out " $tmp_str";
						}
					}
					print $out ")))\n";
					push(@tmp_var, "C_N$nets[$netIndex][1]\_C$commodityIndex\_c$col\_$vName");
					$cnt_var++;
				}
				if($cnt_var == 1){
					print $out "(assert (= $tmp_var[0] true))\n";
				}
				elsif($cnt_var > 0){
					#at-most 1
					print $out "(assert ((_ at-most 1)";
					for my $i(0 .. $#tmp_var){
						print $out " $tmp_var[$i]";
					}
					print $out "))\n";
					#at-least 1
					print $out "(assert ((_ at-least 1)";
					for my $i(0 .. $#tmp_var){
						print $out " $tmp_var[$i]";
					}
					print $out "))\n";
				}
			}
		}
	}
}
my $tmp_str = "";
my @tmp_var = ();
my $cnt_var = 0;
for my $netIndex (0 .. $#nets) {
	for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
		for my $metal (0 .. $numMetalLayer-1) {   
			for my $row (0 .. $numTrackH-1) {
				for my $col (0 .. $numTrackV-1) {
					$vName = "m".$metal."r".$row."c".$col;
					for my $i (0 .. $#{$vedge_out{$vName}}){ # sink
						if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][5][$commodityIndex] &&
							($virtualEdges[$vedge_out{$vName}[$i]][2] eq $keySON)){
							$tmp_str ="N$nets[$netIndex][1]\_";
							$tmp_str.="C$commodityIndex\_";
							$tmp_str.="E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
							push(@tmp_var, $tmp_str);
							$cnt_var++;
						}
					}
				}
			}
		}
	}
}
if($cnt_var > 0){
	#at-most numOuterPins
	print $out "(assert ((_ at-most ".($numOuterPins-2).")";
	for my $i(0 .. $#tmp_var){
		print $out " $tmp_var[$i]";
	}
	print $out "))\n";
	#at-least numOuterPins
	print $out "(assert ((_ at-least ".($numOuterPins-2).")";
	for my $i(0 .. $#tmp_var){
		print $out " $tmp_var[$i]";
	}
	print $out "))\n";
}
$tmp_str = "";
@tmp_var = ();
$cnt_var = 0;
for my $netIndex (0 .. $#nets) {
	for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
		for my $metal (0 .. $numMetalLayer-1) {   
			for my $row (0 .. $numTrackH-1) {
				for my $col (0 .. $numTrackV-1) {
					$vName = "m".$metal."r".$row."c".$col;
					for my $i (0 .. $#{$vedge_out{$vName}}){ # sink
						if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][5][$commodityIndex] &&
							($virtualEdges[$vedge_out{$vName}[$i]][2] eq $keySON_VDD)){
							$tmp_str ="N$nets[$netIndex][1]\_";
							$tmp_str.="C$commodityIndex\_";
							$tmp_str.="E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
							push(@tmp_var, $tmp_str);
							$cnt_var++;
						}
					}
				}
			}
		}
	}
}
if($cnt_var > 0){
	#at-most numOuterPins
	print $out "(assert ((_ at-most 1)";
	for my $i(0 .. $#tmp_var){
		print $out " $tmp_var[$i]";
	}
	print $out "))\n";
	#at-least numOuterPins
	print $out "(assert ((_ at-least 1)";
	for my $i(0 .. $#tmp_var){
		print $out " $tmp_var[$i]";
	}
	print $out "))\n";
}
$tmp_str = "";
@tmp_var = ();;
$cnt_var = 0;
for my $netIndex (0 .. $#nets) {
	for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
		for my $metal (0 .. $numMetalLayer-1) {   
			for my $row (0 .. $numTrackH-1) {
				for my $col (0 .. $numTrackV-1) {
					$vName = "m".$metal."r".$row."c".$col;
					for my $i (0 .. $#{$vedge_out{$vName}}){ # sink
						if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][5][$commodityIndex] &&
							($virtualEdges[$vedge_out{$vName}[$i]][2] eq $keySON_VSS)){
							$tmp_str ="N$nets[$netIndex][1]\_";
							$tmp_str.="C$commodityIndex\_";
							$tmp_str.="E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
							push(@tmp_var, $tmp_str);
							$cnt_var++;
						}
					}
				}
			}
		}
	}
}
if($cnt_var > 0){
	#at-most numOuterPins
	print $out "(assert ((_ at-most 1)";
	for my $i(0 .. $#tmp_var){
		print $out " $tmp_var[$i]";
	}
	print $out "))\n";
	#at-least numOuterPins
	print $out "(assert ((_ at-least 1)";
	for my $i(0 .. $#tmp_var){
		print $out " $tmp_var[$i]";
	}
	print $out "))\n";
}
print "has been written.\n";
print $out "\n";

### Exclusiveness use of VERTEX.  (Only considers incoming flows by nature.)
print "a     2. Exclusiveness use of vertex ";
print $out ";2. Exclusiveness use of vertex for each vertex and every connected edge to the vertex\n";
for my $metal (0 .. $numMetalLayer-1) {   
	for my $row (0 .. $numTrackH-1) {
		for my $col (0 .. $numTrackV-1) {
			$vName = "m".$metal."r".$row."c".$col;
			my @tmp_var_net = ();
			my $cnt_var_net = 0;
			for my $netIndex (0 .. $#nets) {
				my $tmp_str = "";
				my @tmp_var = ();
				my $cnt_var = 0;
				for my $i (0 .. $#{$edge_in{$vName}}){ # incoming
					$tmp_str ="N$nets[$netIndex][1]\_";
					$tmp_str.="E_$udEdges[$edge_in{$vName}[$i]][1]_$vName";
					push(@tmp_var, $tmp_str);
					$cnt_var++;
				}
				for my $i (0 .. $#{$edge_out{$vName}}){ # incoming
					$tmp_str ="N$nets[$netIndex][1]\_";
					$tmp_str.="E_$vName\_$udEdges[$edge_out{$vName}[$i]][2]";
					push(@tmp_var, $tmp_str);
					$cnt_var++;
				}
				for my $i (0 .. $#{$vedge_out{$vName}}){ # incoming
					if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][3]){
						$tmp_str ="N$nets[$netIndex][1]\_";
						$tmp_str.="E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
						push(@tmp_var, $tmp_str);
						$cnt_var++;
					}
					for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
						if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][5][$commodityIndex]){
							$tmp_str ="N$nets[$netIndex][1]\_";
							$tmp_str.="E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
							push(@tmp_var, $tmp_str);
							$cnt_var++;
						}
					}
				}
				my $tmp_enc = "C_N$nets[$netIndex][1]\_$vName";
				if($cnt_var>0){
					print $out "(declare-const $tmp_enc Bool)\n";
					push(@tmp_var_net, $tmp_enc);
					$cnt_var_net++;

					print $out "(assert (= $tmp_enc (or";
					for my $i(0 .. $#tmp_var){
						print $out " $tmp_var[$i]";
					}
					print $out ")))\n";
				}
			}
			if($cnt_var_net>0){
				# at-most 1
				print $out  "(assert ((_ at-most 1)";
				for my $i(0 .. $#tmp_var_net){
					print $out  " $tmp_var_net[$i]";
				}
				print $out  "))\n";
			}	
		}
	}
}
for my $netIndex (0 .. $#nets) {
	my $tmp_str = "";
	my @tmp_var = ();
	my $cnt_var = 0;
	for my $col (0 .. $numTrackV-1) {
		print $out "(declare-const C_N$nets[$netIndex][1]\_c$col\_$nets[$netIndex][3] Bool)\n";
		print $out "(assert (= C_N$nets[$netIndex][1]\_c$col\_$nets[$netIndex][3] (or";
		for my $metal (0 .. $numMetalLayer-1) {   
			for my $row (0 .. $numTrackH-1) {
				$vName = "m".$metal."r".$row."c".$col;
				for my $i (0 .. $#{$vedge_out{$vName}}){ # incoming
					if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][3]){
						$tmp_str ="N$nets[$netIndex][1]\_";
						$tmp_str.="E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
						print $out " $tmp_str";
					}
				}
			}
		}
		print $out ")))\n";
		push(@tmp_var, "C_N$nets[$netIndex][1]\_c$col\_$nets[$netIndex][3]");
		$cnt_var++;
	}
	if($cnt_var == 1){
		print $out "(assert (= $tmp_var[0] true))\n";
	}
	elsif($cnt_var > 0){
		#at-most 1
		print $out  "(assert ((_ at-most 1)";
		for my $i(0 .. $#tmp_var){
			print $out  " $tmp_var[$i]";
		}
		print $out  "))\n";
		#at-least 1
		print $out  "(assert ((_ at-least 1)";
		for my $i(0 .. $#tmp_var){
			print $out  " $tmp_var[$i]";
		}
		print $out  "))\n";
	}
}
$tmp_str = "";
@tmp_var = ();
$cnt_var = 0;
for my $netIndex (0 .. $#nets) {
	for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
		my $tmp_str = "";
		my @tmp_var = ();
		my $cnt_var = 0;
		for my $col (0 .. $numTrackV-1) {
			if($nets[$netIndex][5][$commodityIndex] ne $keySON && $nets[$netIndex][5][$commodityIndex] ne $keySON_VDD &&
				$nets[$netIndex][5][$commodityIndex] ne $keySON_VSS){
				print $out "(declare-const C_N$nets[$netIndex][1]\_c$col\_$nets[$netIndex][5][$commodityIndex] Bool)\n";
				print $out "(assert (= C_N$nets[$netIndex][1]\_c$col\_$nets[$netIndex][5][$commodityIndex] (or";
				for my $metal (0 .. $numMetalLayer-1) {   
					for my $row (0 .. $numTrackH-1) {
						$vName = "m".$metal."r".$row."c".$col;
						for my $i (0 .. $#{$vedge_out{$vName}}){ # incoming
							if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][5][$commodityIndex] &&
								($virtualEdges[$vedge_out{$vName}[$i]][2] ne $keySON && $virtualEdges[$vedge_out{$vName}[$i]][2] ne $keySON_VDD && $virtualEdges[$vedge_out{$vName}[$i]][2] ne $keySON_VSS)){
								$tmp_str ="N$nets[$netIndex][1]\_";
								$tmp_str.="E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
								print $out " $tmp_str";
							}
						}
					}
				}
				print $out ")))\n";
				push(@tmp_var, "C_N$nets[$netIndex][1]\_c$col\_$nets[$netIndex][5][$commodityIndex]");
				$cnt_var++;
			}
		}
		if($cnt_var == 1){
			print $out "(assert (= $tmp_var[0] true))\n";
		}
		elsif($cnt_var > 0){
			#at-most 1
			print $out  "(assert ((_ at-most 1)";
			for my $i(0 .. $#tmp_var){
				print $out  " $tmp_var[$i]";
			}
			print $out  "))\n";
			#at-least 1
			print $out  "(assert ((_ at-least 1)";
			for my $i(0 .. $#tmp_var){
				print $out  " $tmp_var[$i]";
			}
			print $out  "))\n";
		}
	}
}
$tmp_str = "";
@tmp_var = ();
$cnt_var = 0;
for my $netIndex (0 .. $#nets) {
	for my $metal (0 .. $numMetalLayer-1) {   
		for my $row (0 .. $numTrackH-1) {
			for my $col (0 .. $numTrackV-1) {
				$vName = "m".$metal."r".$row."c".$col;
				for my $i (0 .. $#{$vedge_out{$vName}}){ # incoming
					for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
						if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][5][$commodityIndex] &&
							($virtualEdges[$vedge_out{$vName}[$i]][2] eq $keySON)){
							$tmp_str ="N$nets[$netIndex][1]\_";
							$tmp_str.="E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
							push(@tmp_var, $tmp_str);
							$cnt_var++;
						}
					}
				}
			}
		}
	}
}
if($cnt_var > 0){
	#at-most numOuterPins
	print $out "(assert ((_ at-most ".($numOuterPins-2).")";
	for my $i(0 .. $#tmp_var){
		print $out  " $tmp_var[$i]";
	}
	print $out  "))\n";
	#at-least numOuterPins
	print $out "(assert ((_ at-least ".($numOuterPins-2).")";
	for my $i(0 .. $#tmp_var){
		print $out  " $tmp_var[$i]";
	}
	print $out  "))\n";
}
$tmp_str = "";
@tmp_var = ();
$cnt_var = 0;
for my $netIndex (0 .. $#nets) {
	for my $metal (0 .. $numMetalLayer-1) {   
		for my $row (0 .. $numTrackH-1) {
			for my $col (0 .. $numTrackV-1) {
				$vName = "m".$metal."r".$row."c".$col;
				for my $i (0 .. $#{$vedge_out{$vName}}){ # incoming
					for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
						if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][5][$commodityIndex] &&
							($virtualEdges[$vedge_out{$vName}[$i]][2] eq $keySON_VDD)){
							$tmp_str ="N$nets[$netIndex][1]\_";
							$tmp_str.="E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
							push(@tmp_var, $tmp_str);
							$cnt_var++;
						}
					}
				}
			}
		}
	}
}
if($cnt_var > 0){
	#at-most numOuterPins
	print $out "(assert ((_ at-most 1)";
	for my $i(0 .. $#tmp_var){
		print $out  " $tmp_var[$i]";
	}
	print $out  "))\n";
	#at-least numOuterPins
	print $out "(assert ((_ at-least 1)";
	for my $i(0 .. $#tmp_var){
		print $out  " $tmp_var[$i]";
	}
	print $out  "))\n";
}
$tmp_str = "";
@tmp_var = ();
$cnt_var = 0;
for my $netIndex (0 .. $#nets) {
	for my $metal (0 .. $numMetalLayer-1) {   
		for my $row (0 .. $numTrackH-1) {
			for my $col (0 .. $numTrackV-1) {
				$vName = "m".$metal."r".$row."c".$col;
				for my $i (0 .. $#{$vedge_out{$vName}}){ # incoming
					for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
						if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][5][$commodityIndex] &&
							($virtualEdges[$vedge_out{$vName}[$i]][2] eq $keySON_VSS)){
							$tmp_str ="N$nets[$netIndex][1]\_";
							$tmp_str.="E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
							push(@tmp_var, $tmp_str);
							$cnt_var++;
						}
					}
				}
			}
		}
	}
}
if($cnt_var > 0){
	#at-most numOuterPins
	print $out "(assert ((_ at-most 1)";
	for my $i(0 .. $#tmp_var){
		print $out  " $tmp_var[$i]";
	}
	print $out  "))\n";
	#at-least numOuterPins
	print $out "(assert ((_ at-least 1)";
	for my $i(0 .. $#tmp_var){
		print $out  " $tmp_var[$i]";
	}
	print $out  "))\n";
}
print "has been written.\n";
print $out "\n";

### EDGE assignment  (Assign edges based on commodity information.)
print "a     3. Edge assignment ";
print $out ";3. Edge assignment for each edge for every net\n";
for my $netIndex (0 .. $#nets) {
	for my $udeIndex (0 .. $#udEdges) {
		for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
			my $tmp_com = "N$nets[$netIndex][1]\_C$commodityIndex\_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2]";
			my $tmp_net = "N$nets[$netIndex][1]\_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2]";
			print $out "(assert (ite (= $tmp_com true) (= $tmp_net true) (= 1 1)))\n";
		}
	}

	for my $vEdgeIndex (0 .. $#virtualEdges) {
		my $isInNet = 0;
		if ($virtualEdges[$vEdgeIndex][2] =~ /^pin/) { # source
			if($virtualEdges[$vEdgeIndex][2] eq $nets[$netIndex][3]){
				$isInNet = 1;
			}
			if($isInNet == 1){
				my $tmp_net = "N$nets[$netIndex][1]\_E_$virtualEdges[$vEdgeIndex][1]_$virtualEdges[$vEdgeIndex][2]";
				print $out "(assert (= $tmp_net (or";
				for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
					my $tmp_com = "N$nets[$netIndex][1]\_C$commodityIndex\_E_$virtualEdges[$vEdgeIndex][1]_$virtualEdges[$vEdgeIndex][2]";
					print $out " $tmp_com";
				}
				print $out ")))\n";
			}
			$isInNet = 0;
			for my $i (0 .. $nets[$netIndex][4]-1){
				if($virtualEdges[$vEdgeIndex][2] eq $nets[$netIndex][5][$i]){
					$isInNet = 1;
				}
			}
			if($isInNet == 1){
				my $tmp_net = "N$nets[$netIndex][1]\_E_$virtualEdges[$vEdgeIndex][1]_$virtualEdges[$vEdgeIndex][2]";
				print $out "(assert (= $tmp_net (or";
				for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
					if($virtualEdges[$vEdgeIndex][2] eq $nets[$netIndex][5][$commodityIndex]){
						my $tmp_com = "N$nets[$netIndex][1]\_C$commodityIndex\_E_$virtualEdges[$vEdgeIndex][1]_$virtualEdges[$vEdgeIndex][2]";
						print $out " $tmp_com";
					}
				}
				print $out ")))\n";
			}
		}
	}
}
print "has been written.\n";
print $out "\n";
### Exclusiveness use of EDGES + Metal segment assignment by using edge usage information
print "a     4. Exclusiveness use of edge ";
print $out ";4. Exclusiveness use of each edge + Metal segment assignment by using edge usage information\n";
for my $udeIndex (0 .. $#udEdges) {
	my $tmp_str="";
	my @tmp_var = ();
	my $cnt_var = 0;
	for my $netIndex (0 .. $#nets) {
		$tmp_str ="N$nets[$netIndex][1]\_";
		$tmp_str.="E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2]";
		push(@tmp_var, $tmp_str);
		$cnt_var++;
	}
	my $tmp_str_metal = "M_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2]";
	if($cnt_var>0){
		# OR
		print $out "(assert (= $tmp_str_metal (or";
		for my $i(0 .. $#tmp_var){
			print $out " $tmp_var[$i]";
		}
		print $out ")))\n";
		# at-most 1
		print $out "(assert ((_ at-most 1)";
		for my $i(0 .. $#tmp_var){
			print $out " $tmp_var[$i]";
		}
		print $out "))\n";
	}
}
for my $vEdgeIndex (0 .. $#virtualEdges) {
	my $tmp_str="";
	my @tmp_var = ();
	my $cnt_var = 0;
	for my $netIndex (0 .. $#nets) {
		my $isInNet = 0;
		if ($virtualEdges[$vEdgeIndex][2] =~ /^pin/) { # source
			if($virtualEdges[$vEdgeIndex][2] eq $nets[$netIndex][3]){
				$isInNet = 1;
			}
			if($isInNet == 1){
				$tmp_str ="N$nets[$netIndex][1]\_";
				$tmp_str.="E_$virtualEdges[$vEdgeIndex][1]_$virtualEdges[$vEdgeIndex][2]";
				push(@tmp_var, $tmp_str);
				$cnt_var++;
			}
			$isInNet = 0;
			for my $i (0 .. $nets[$netIndex][4]-1){
				if($virtualEdges[$vEdgeIndex][2] eq $nets[$netIndex][5][$i]){
					$isInNet = 1;
				}
			}
			if($isInNet == 1){
				$tmp_str ="N$nets[$netIndex][1]\_";
				$tmp_str.="E_$virtualEdges[$vEdgeIndex][1]_$virtualEdges[$vEdgeIndex][2]";
				push(@tmp_var, $tmp_str);
				$cnt_var++;
			}
		}
	}
	my $tmp_str_metal = "M_$virtualEdges[$vEdgeIndex][1]_$virtualEdges[$vEdgeIndex][2]";
	if($cnt_var>0){
		if($cnt_var==1){
			print $out "(assert (= $tmp_var[0] $tmp_str_metal))\n";
		}
		else{
			# OR
			print $out "(assert (= $tmp_str_metal (or";
			for my $i(0 .. $#tmp_var){
				print $out " $tmp_var[$i]";
			}
			print $out ")))\n";
			# at-most 1
			print $out "(assert ((_ at-most 1)";
			for my $i(0 .. $#tmp_var){
				print $out " $tmp_var[$i]";
			}
			print $out "))\n";
		}
	}
}
print "has been written.\n";
print $out "\n";

print "a     5. Exclusiveness use of S/D Nodes ";
print $out ";5. Exclusiveness use of S/D Nodes per each FET\n";
for my $i (0 .. $numInstance -1) {
	my $source = $h_instIdx_S{$i};
	my $drain = $h_instIdx_D{$i};
	for my $tier (0 .. $numTier-1){
		my $netIndex = $h_netName_idx{$pins[$h_pinId_idx{$source}][1]};
		my $row = -1;
		if($i <= $lastIdxPMOS) {
			$row = $h_track{$tier."_P"};
		}
		else{
			$row = $h_track{$tier."_N"};
		}
		for my $metal ($tier .. $tier+1){
			my $tmp_str = "";
			my @tmp_var_S = ();
			my $cnt_var_S = 0;
			my @tmp_var_D = ();
			my $cnt_var_D = 0;
			for my $col (0 .. $numTrackV-1) {
				my $vName1 = "m".($metal*2)."r".$row."c".$col;
				for my $i (0 .. $#{$vedge_out{$vName1}}){ # incoming
					if($virtualEdges[$vedge_out{$vName1}[$i]][2] eq $source){
						$tmp_str ="M_$vName1\_$virtualEdges[$vedge_out{$vName1}[$i]][2]";
						push(@tmp_var_S, $tmp_str);
						$cnt_var_S++;
					}
					if($virtualEdges[$vedge_out{$vName1}[$i]][2] eq $drain){
						$tmp_str ="M_$vName1\_$virtualEdges[$vedge_out{$vName1}[$i]][2]";
						push(@tmp_var_D, $tmp_str);
						$cnt_var_D++;
					}
				}
			}
			if($cnt_var_S > 0 && $cnt_var_D){
				print $out ";(assert ((_ at-most 1) (or";
				for my $i(0 .. $#tmp_var_S){
					print $out  " $tmp_var_S[$i]";
				}
				print $out ") (or";
				for my $i(0 .. $#tmp_var_D){
					print $out  " $tmp_var_D[$i]";
				}
				print $out  ")))\n";
			}
			for my $i(0 .. $#tmp_var_S){
				print $out "(assert ((_ at-most 1) $tmp_var_S[$i] $tmp_var_D[$i]))\n";
				print $out "(assert ((_ at-most 1) $tmp_var_D[$i] $tmp_var_S[$i]))\n";
			}
		}
	}
}

print "has been written.\n";
print $out "\n";

print "a     6. VIA enclosure";
print $out ";6. VIA enclosure\n";
foreach my $net(sort(keys %h_extnets)){
	my $netIndex = $h_idx{$net};
	for my $metal ($numMetalLayer-2 .. $numMetalLayer-2) {
		for my $row (0 .. $numTrackH-1) {
			for my $col (0 .. $numTrackV-1) {
				$vName = "m".$metal."r".$row."c".$col;
				my $tmp1 = "N$nets[$netIndex][1]_E_$vName\_$vertices{$vName}[5][4]";
				my $vName_u = $vertices{$vName}[5][4];
				my $tmp3 = "";
				my $tmp4 = "";
			
				$tmp3 = "N$nets[$netIndex][1]_E";
				# Left Vertex
				if ($vertices{$vName_u}[5][0] ne "null") {
					$tmp3.="_$vertices{$vName_u}[5][0]_$vName_u";
				}
				elsif ($vertices{$vName_u}[5][0] eq "null") {
					$tmp3 = "null";
				}
				# Right Vertex
				$tmp4 ="N$nets[$netIndex][1]_E";
				if ($vertices{$vName_u}[5][1] ne "null") {
					$tmp4.="_$vName_u\_$vertices{$vName_u}[5][1]";
				}
				elsif ($vertices{$vName_u}[5][1] eq "null") {
					$tmp4 = "null";
				}
				if($tmp3 eq "null"){
					if($tmp4 eq "null"){
						print $out "(assert (ite (= $tmp1 true) (= true false) (= true true)))\n";
					}
					elsif($tmp4 ne "null"){
						print $out "(assert (ite (= $tmp1 true) (= $tmp4 true) (= true true)))\n";
					}
				}
				elsif($tmp3 ne "null"){
					if($tmp4 eq "null"){
						print $out "(assert (ite (= $tmp1 true) (= $tmp3 true) (= true true)))\n";
					}
					elsif($tmp4 ne "null"){
						print $out "(assert (ite (= $tmp1 true) ((_ at-least 1) $tmp3 $tmp4) (= true true)))\n";
					}
				}
			}
		}
	}
}
print "has been written.\n";
print $out "\n";

print "a     7. Pin Accessibility Rule ";
print $out ";7. Pin Accessibility Rule\n";

### Pin Accessibility Rule : External Pin Nets(except VDD/VSS) should have at-least $MPO true edges for top-Layer or (top-1) layer(with opening)
my $metal = $numMetalLayer - 2;
my %h_tmp = ();

# Vertical
foreach my $net(sort(keys %h_extnets)){
	my $netIndex = $h_idx{$net};
	for my $col (0 .. $numTrackV-1) {
		if(!exists($h_tmp{$net."_".$col})){
			for my $row (0 .. $numTrackH-1) {
				$vName = "m".$metal."r".$row."c".$col;
				for my $i (0 .. $#{$vedge_out{$vName}}){ # incoming
					for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
						if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][5][$commodityIndex] && $virtualEdges[$vedge_out{$vName}[$i]][2] eq $keySON){
							if(!exists($h_tmp{$net."_".$col})){
								$h_tmp{$net."_".$col} = 1;
							}
							my $tmp_str ="N$nets[$netIndex][1]\_";
							$tmp_str.="E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
							print $out "(assert (ite (and (= N$net\_LM_TRACK false) (= $tmp_str true)) ((_ at-least ".($MPO_Parameter).")";
							for my $row2 (0 .. $numTrackH-1) {
								my $tmp_str2 = "";
								my @tmp_var = ();
								my $cnt_var = 0;
								my @tmp_var_1 = ();
								my $cnt_var_1 = 0;

								my $vName2 = "m".$metal."r".$row2."c".$col;
								my $selfF = "";
								my $selfB = "";
								if(exists($vertices{$vName2}) && $vertices{$vName2}[5][2] ne "null"){
									$selfF = "N$net\_E_$vertices{$vName2}[5][2]\_$vName2";
									push(@tmp_var_1, $selfF);
									$cnt_var_1++;
								}
								if(exists($vertices{$vName2}) && $vertices{$vName2}[5][3] ne "null"){
									$selfB = "N$net\_E_$vName2\_$vertices{$vName2}[5][3]";
									push(@tmp_var_1, $selfB);
									$cnt_var_1++;
								}
								print $out " (or";
								for my $mar(0 .. $MAR_Parameter){
									$cnt_var = 0;
									@tmp_var = ();
									# Upper Layer => Left = EOL, Right = EOL+MAR should be keepout region from other nets
									$vName2 = "m".($metal+1)."r".$row2."c".$col;
									for my $netIndex2 (0 .. $#nets) {
										if($nets[$netIndex2][1] ne $net){
											my $pre_vName = $vName2;
											for my $i(0 .. ($EOL_Parameter + $mar)){
												if(exists($vertices{$pre_vName}) && $vertices{$pre_vName}[5][0] ne "null"){
													$tmp_str2 = "N$nets[$netIndex2][1]_E_$vertices{$pre_vName}[5][0]\_$pre_vName";
													push(@tmp_var, $tmp_str2);
													$cnt_var++;
													$pre_vName = $vertices{$pre_vName}[5][0];
												}
												else{
													next;
												}
											}
											$pre_vName = $vName2;
											for my $i(0 .. ($MAR_Parameter - $mar + $EOL_Parameter)){
												if(exists($vertices{$pre_vName}) && $vertices{$pre_vName}[5][1] ne "null"){
													$tmp_str2 = "N$nets[$netIndex2][1]_E_$pre_vName\_$vertices{$pre_vName}[5][1]";
													push(@tmp_var, $tmp_str2);
													$cnt_var++;
													$pre_vName = $vertices{$pre_vName}[5][1];
												}
												else{
													next;
												}
											}
										}
									}
									if($cnt_var_1>0){
										if($cnt_var_1 == 1){
											print $out " (and (= $tmp_var_1[0] true)";
											for my $m(0 .. $#tmp_var){
												print $out " (= $tmp_var[$m] false)";
											}
											print $out ")";
										}
										else{
											print $out " (and (or";
											for my $m(0 .. $#tmp_var_1){
												print $out " (= $tmp_var_1[$m] true)";
											}
											print $out ")";
											for my $m(0 .. $#tmp_var){
												print $out " (= $tmp_var[$m] false)";
											}
											print $out ")";
										}
									}
								}
								print $out ")";
							}
							print $out ") (= true true)))\n";
						}
					}
				}
			}
		}
	}
}
print "has been written.\n";
print $out "\n";
print "a     8. Net Consistency";
print $out ";8. Net Consistency\n";
### DATA STRUCTURE:  ADJACENT_VERTICES [0:Left] [1:Right] [2:Front] [3:Back] [4:Up] [5:Down] [6:FL] [7:FR] [8:BL] [9:BR]
# All Net Variables should be connected to flow variable though it is not a direct connection
my %h_tmp = ();
foreach my $net(sort(keys %h_extnets)){
	my $netIndex = $h_idx{$net};
	for my $metal ($numMetalLayer-2 .. $numMetalLayer-2) {   
		for my $col (0 .. $numTrackV-1) {
			if(!exists($h_tmp{$net."_".$col})){
				for my $row (0 .. $numTrackH-1) {
					$vName = "m".$metal."r".$row."c".$col;
					for my $i (0 .. $#{$vedge_out{$vName}}){ # incoming
						for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
							if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][5][$commodityIndex] && $virtualEdges[$vedge_out{$vName}[$i]][2] eq $keySON){
								if(!exists($h_tmp{$net."_".$col})){
									$h_tmp{$net."_".$col} = 1;
								}
								my $tmp_str_e ="N$nets[$netIndex][1]\_";
								$tmp_str_e.="E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
								for my $row2 (0 .. $numTrackH-1) {
									my $vName2 = "m".$metal."r".$row2."c".$col;
									my $tmp_str = "";
									my @tmp_var_self = ();
									my @tmp_var_self_c = ();
									my $cnt_var_self = 0;
									my $cnt_var_self_c = 0;

									if(exists($vertices{$vName2}) && $vertices{$vName2}[5][3] ne "null"){
										$tmp_str = "N$nets[$netIndex][1]\_E_$vName2\_$vertices{$vName2}[5][3]";
										push(@tmp_var_self, $tmp_str);
										$cnt_var_self++;
										for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
											$tmp_str = "N$nets[$netIndex][1]\_C$commodityIndex\_E_$vName2\_$vertices{$vName2}[5][3]";
											push(@tmp_var_self_c, $tmp_str);
											$cnt_var_self_c++;
										}
										print $out "(assert (ite (and (= N$net\_LM_TRACK false) (= $tmp_str_e true)";
										print $out " (= $tmp_var_self[0] true)";
										for my $i(0 .. $#tmp_var_self_c){
											print $out " (= $tmp_var_self_c[$i] false)";
										}
										print $out ") ((_ at-least 1)";
										my @tmp_var_com = ();
										my $cnt_var_com = 0;
										my $vName3 = "m".$metal."r".($row2+1)."c".$col;
										if(exists($vertices{$vName3}) && $vertices{$vName3}[5][3] ne "null"){
											for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
												$tmp_str = "N$nets[$netIndex][1]\_C$commodityIndex\_E_$vName3\_$vertices{$vName3}[5][3]";
												push(@tmp_var_com, $tmp_str);
												$cnt_var_com++;
											}
										}
										if(!($row2+1 == $h_track{($numTier-1)."_P"} || $row2+1 == $h_track{($numTier-1)."_N"})){
											if(exists($vertices{$vName3}) && $vertices{$vName3}[5][5] ne "null"){
												for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
													$tmp_str = "N$nets[$netIndex][1]\_C$commodityIndex\_E_$vertices{$vName3}[5][5]\_$vName3";
													push(@tmp_var_com, $tmp_str);
													$cnt_var_com++;
												}
											}
										}
										if(exists($vertices{$vName3}) && $vertices{$vName3}[5][4] ne "null"){
											for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
												$tmp_str = "N$nets[$netIndex][1]\_C$commodityIndex\_E_$vName3\_$vertices{$vName3}[5][4]";
												push(@tmp_var_com, $tmp_str);
												$cnt_var_com++;
											}
										}
										if($cnt_var_com==1){
											for my $m(0 .. $#tmp_var_com){
												print $out " $tmp_var_com[$m]";
											}
										}
										elsif($cnt_var_com>=1){
											print $out " (or";
											for my $m(0 .. $#tmp_var_com){
												print $out " $tmp_var_com[$m]";
											}
											print $out ")";
										}
										for my $row3 ($row2+1 .. $numTrackH-1){
											my @tmp_var_net = ();
											my @tmp_var_com = ();
											my $cnt_var_net = 0;
											my $cnt_var_com = 0;
											for my $j (0 .. $row3-$row2-1){
												my $vName2 = "m".$metal."r".($row2+1+$j)."c".($col);
												if(exists($vertices{$vName2}) && $vertices{$vName2}[5][3] ne "null"){
													$tmp_str = "N$nets[$netIndex][1]\_E_$vName2\_$vertices{$vName2}[5][3]";
													push(@tmp_var_net, $tmp_str);
													$cnt_var_net++;
												}
											}
											my $vName3 = "m".$metal."r".($row3+1)."c".($col);
											if(exists($vertices{$vName3}) && $vertices{$vName3}[5][3] ne "null"){
												for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
													$tmp_str = "N$nets[$netIndex][1]\_C$commodityIndex\_E_$vName3\_$vertices{$vName3}[5][3]";
													push(@tmp_var_com, $tmp_str);
													$cnt_var_com++;
												}
											}
											if(!($row3+1 == $h_track{($numTier-1)."_P"} || $row3+1 == $h_track{($numTier-1)."_N"})){
												if(exists($vertices{$vName3}) && $vertices{$vName3}[5][5] ne "null"){
													for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
														$tmp_str = "N$nets[$netIndex][1]\_C$commodityIndex\_E_$vertices{$vName3}[5][5]\_$vName3";
														push(@tmp_var_com, $tmp_str);
														$cnt_var_com++;
													}
												}
											}
											if(exists($vertices{$vName3}) && $vertices{$vName3}[5][4] ne "null"){
												for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
													$tmp_str = "N$nets[$netIndex][1]\_C$commodityIndex\_E_$vName3\_$vertices{$vName3}[5][4]";
													push(@tmp_var_com, $tmp_str);
													$cnt_var_com++;
												}
											}
											if($cnt_var_com==1){
												for my $m(0 .. $#tmp_var_com){
													print $out " (and $tmp_var_com[$m]";
												}
												for my $m(0 .. $#tmp_var_net){
													print $out " $tmp_var_net[$m]";
												}
												print $out ")";
											}
											elsif($cnt_var_com>=1){
												print $out " (and (or";
												for my $m(0 .. $#tmp_var_com){
													print $out " $tmp_var_com[$m]";
												}
												print $out ")";
												for my $m(0 .. $#tmp_var_net){
													print $out " $tmp_var_net[$m]";
												}
												print $out ")";
											}
										}

										my @tmp_var_com = ();
										my $cnt_var_com = 0;
										my $vName3 = "m".$metal."r".$row2."c".($col);
										if(exists($vertices{$vName3}) && $vertices{$vName3}[5][2] ne "null"){
											for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
												$tmp_str = "N$nets[$netIndex][1]\_C$commodityIndex\_E_$vertices{$vName3}[5][2]\_$vName3";
												push(@tmp_var_com, $tmp_str);
												$cnt_var_com++;
											}
										}
										if(!($row2 == $h_track{($numTier-1)."_P"} || $row2 == $h_track{($numTier-1)."_N"})){
											if(exists($vertices{$vName3}) && $vertices{$vName3}[5][5] ne "null"){
												for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
													$tmp_str = "N$nets[$netIndex][1]\_C$commodityIndex\_E_$vertices{$vName3}[5][5]\_$vName3";
													push(@tmp_var_com, $tmp_str);
													$cnt_var_com++;
												}
											}
										}
										if(exists($vertices{$vName3}) && $vertices{$vName3}[5][4] ne "null"){
											for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
												$tmp_str = "N$nets[$netIndex][1]\_C$commodityIndex\_E_$vName3\_$vertices{$vName3}[5][4]";
												push(@tmp_var_com, $tmp_str);
												$cnt_var_com++;
											}
										}
										if($cnt_var_com==1){
											for my $m(0 .. $#tmp_var_com){
												print $out " $tmp_var_com[$m]";
											}
										}
										elsif($cnt_var_com>=1){
											print $out " (or";
											for my $m(0 .. $#tmp_var_com){
												print $out " $tmp_var_com[$m]";
											}
											print $out ")";
										}
										for my $row3 (0 .. $row2-1){
											my @tmp_var_net = ();
											my @tmp_var_com = ();
											my $cnt_var_net = 0;
											my $cnt_var_com = 0;
											for my $j (0 .. $row3){
												my $vName2 = "m".$metal."r".($row2-$j)."c".($col);
												if(exists($vertices{$vName2}) && $vertices{$vName2}[5][2] ne "null"){
													$tmp_str = "N$nets[$netIndex][1]\_E_$vertices{$vName2}[5][2]\_$vName2";
													push(@tmp_var_net, $tmp_str);
													$cnt_var_net++;
												}
											}
											my $vName3 = "m".$metal."r".($row2-$row3-1)."c".($col);
											if(exists($vertices{$vName3}) && $vertices{$vName3}[5][2] ne "null"){
												for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
													$tmp_str = "N$nets[$netIndex][1]\_C$commodityIndex\_E_$vertices{$vName3}[5][2]\_$vName3";
													push(@tmp_var_com, $tmp_str);
													$cnt_var_com++;
												}
											}
											if(!(($row2-$row3-1) == $h_track{($numTier-1)."_P"} || ($row2-$row3-1) == $h_track{($numTier-1)."_N"})){
												if(exists($vertices{$vName3}) && $vertices{$vName3}[5][5] ne "null"){
													for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
														$tmp_str = "N$nets[$netIndex][1]\_C$commodityIndex\_E_$vertices{$vName3}[5][5]\_$vName3";
														push(@tmp_var_com, $tmp_str);
														$cnt_var_com++;
													}
												}
											}
											if(exists($vertices{$vName3}) && $vertices{$vName3}[5][4] ne "null"){
												for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
													$tmp_str = "N$nets[$netIndex][1]\_C$commodityIndex\_E_$vName3\_$vertices{$vName3}[5][4]";
													push(@tmp_var_com, $tmp_str);
													$cnt_var_com++;
												}
											}
											if($cnt_var_com==1){
												for my $m(0 .. $#tmp_var_com){
													print $out " (and $tmp_var_com[$m]";
												}
												for my $m(0 .. $#tmp_var_net){
													print $out " $tmp_var_net[$m]";
												}
												print $out ")";
											}
											elsif($cnt_var_com>=1){
												print $out " (and (or";
												for my $m(0 .. $#tmp_var_com){
													print $out " $tmp_var_com[$m]";
												}
												print $out ")";
												for my $m(0 .. $#tmp_var_net){
													print $out " $tmp_var_net[$m]";
												}
												print $out ")";
											}
										}
										print $out ") (= true true)))\n";
									}
								}
							}
						}
					}
				}
			}
		}
	}
}
print "has been written.\n";
print "\n";

print "a   E. Initial Settings\n";
print $out ";E. Initial Settings\n";

# Multi-Fingered FET : Set Relative positions
print $out ";Multi-fingered FET\n";
my @arr_pmos_group = ();
my @arr_nmos_group = ();
my @arr_pmos_fgroup = ();
my @arr_nmos_fgroup = ();
my %h_mf_info = ();
foreach my $key(sort(keys %h_mf)){
	if(exists($h_mf{$key})){
		my @tmp = $h_mf{$key};
		my $numFinger = $#{@tmp[0]}+1;
		my $step = $numFinger;
		my $last_step = $numFinger % $step;
		my $it = int($numFinger / $step);
		if($it>0){
			for my $j(0 .. $it-1){
				for my $k($j*$step .. ($j+1)*$step-1){
					my $dist = 1;
					if($k==0 && $tmp[0][0] <= $lastIdxPMOS){
						print $out "(assert (bvule x$tmp[0][0] (_ bv".($numTrackV - $step)." $lenV)))\n";
						my $source = $h_instIdx_S{$tmp[0][0]};
						my $gate = $h_instIdx_G{$tmp[0][0]};
						my $drain = $h_instIdx_D{$tmp[0][0]};
						for my $tier (0 .. $numTier-1){
							my $row = $h_track{$tier."_P"};
							for my $metal ($tier*2 .. $tier*2+2){
								my $tmp_str = "";
								for my $col ($numTrackV - $step + 1 .. $numTrackV-1) {
									my $vName1 = "m".($metal)."r".$row."c".$col;
									for my $i (0 .. $#{$vedge_out{$vName1}}){ # incoming
										my $toCol   = (split /[a-z]/, $virtualEdges[$vedge_out{$vName1}[$i]][1])[3];
										if($toCol == $col && ($virtualEdges[$vedge_out{$vName1}[$i]][2] eq $source ||
													$virtualEdges[$vedge_out{$vName1}[$i]][2] eq $gate ||
													$virtualEdges[$vedge_out{$vName1}[$i]][2] eq $drain)){
											$tmp_str ="M_$vName1\_$virtualEdges[$vedge_out{$vName1}[$i]][2]";
											print $out "(assert (= $tmp_str false))\n";
										}
									}
								}
							}
						}
						push(@arr_pmos_group, $tmp[0][0]);
					}
					elsif($k==0){
						print $out "(assert (bvule x$tmp[0][0] (_ bv".($numTrackV - $step)." $lenV)))\n";
						my $source = $h_instIdx_S{$tmp[0][0]};
						my $gate = $h_instIdx_G{$tmp[0][0]};
						my $drain = $h_instIdx_D{$tmp[0][0]};
						for my $tier (0 .. $numTier-1){
							my $row = $h_track{$tier."_N"};
							for my $metal ($tier*2 .. $tier*2+2){
								my $tmp_str = "";
								for my $col ($numTrackV - $step + 1 .. $numTrackV-1) {
									my $vName1 = "m".($metal)."r".$row."c".$col;
									for my $i (0 .. $#{$vedge_out{$vName1}}){ # incoming
										my $toCol   = (split /[a-z]/, $virtualEdges[$vedge_out{$vName1}[$i]][1])[3];
										if($toCol == $col && ($virtualEdges[$vedge_out{$vName1}[$i]][2] eq $source ||
													$virtualEdges[$vedge_out{$vName1}[$i]][2] eq $gate ||
													$virtualEdges[$vedge_out{$vName1}[$i]][2] eq $drain)){
											$tmp_str ="M_$vName1\_$virtualEdges[$vedge_out{$vName1}[$i]][2]";
											print $out "(assert (= $tmp_str false))\n";
										}
									}
								}
							}
						}
						push(@arr_nmos_group, $tmp[0][0]);
					}
					for my $l($j*$step .. ($j+1)*$step-1){
						if($k>=$l) { next;}
						print $out "(assert (and (= t$tmp[0][$l] t$tmp[0][$k]) (= x$tmp[0][$l] (bvadd x$tmp[0][$k] (_ bv".($dist)." $lenV)))))\n";
						if($k==0){
							$h_mf_info{"$tmp[0][$k]_$tmp[0][$l]"} = $dist;
							print $out "(assert (bvule x$tmp[0][$l] (_ bv".($numTrackV - $step+$dist)." $lenV)))\n";
							my $source = $h_instIdx_S{$tmp[0][$l]};
							my $gate = $h_instIdx_G{$tmp[0][$l]};
							my $drain = $h_instIdx_D{$tmp[0][$l]};
							for my $tier (0 .. $numTier-1){
								my $row = -1;
								if($tmp[0][0] <= $lastIdxPMOS){
									$row = $h_track{$tier."_P"};
								}
								else{
									$row = $h_track{$tier."_N"};
								}
								for my $metal ($tier*2 .. $tier*2+2){
									my $tmp_str = "";
									for my $col ($numTrackV - $step+1+$dist .. $numTrackV-1) {
										my $vName1 = "m".($metal)."r".$row."c".$col;
										for my $i (0 .. $#{$vedge_out{$vName1}}){ # incoming
											my $toCol   = (split /[a-z]/, $virtualEdges[$vedge_out{$vName1}[$i]][1])[3];
											if($toCol == $col && ($virtualEdges[$vedge_out{$vName1}[$i]][2] eq $source ||
														$virtualEdges[$vedge_out{$vName1}[$i]][2] eq $gate ||
														$virtualEdges[$vedge_out{$vName1}[$i]][2] eq $drain)){
												$tmp_str ="M_$vName1\_$virtualEdges[$vedge_out{$vName1}[$i]][2]";
												print $out "(assert (= $tmp_str false))\n";
											}
										}
									}
									for my $col (0 .. $dist-1) {
										my $vName1 = "m".($metal)."r".$row."c".$col;
										for my $i (0 .. $#{$vedge_out{$vName1}}){ # incoming
											my $toCol   = (split /[a-z]/, $virtualEdges[$vedge_out{$vName1}[$i]][1])[3];
											if($toCol == $col && ($virtualEdges[$vedge_out{$vName1}[$i]][2] eq $source ||
														$virtualEdges[$vedge_out{$vName1}[$i]][2] eq $gate ||
														$virtualEdges[$vedge_out{$vName1}[$i]][2] eq $drain)){
												$tmp_str ="M_$vName1\_$virtualEdges[$vedge_out{$vName1}[$i]][2]";
												print $out "(assert (= $tmp_str false))\n";
											}
										}
									}
								}
							}
							my $source_s = $h_instIdx_S{$tmp[0][$k]};
							my $drain_s = $h_instIdx_D{$tmp[0][$k]};
							for my $tier (0 .. $numTier-1){
								my $row = -1;
								if($tmp[0][0] <= $lastIdxPMOS){
									$row = $h_track{$tier."_P"};
								}
								else{
									$row = $h_track{$tier."_N"};
								}
								for my $metal ($tier*2 .. $tier*2+2){
									my $tmp_str = "";
									my $tmp_str_source1 = "";
									my $tmp_str_source2 = "";
									my $tmp_str_drain1 = "";
									my $tmp_str_drain2 = "";
									for my $col (0 .. $numTrackV - 1) {
										my $tmp_str_source1_t = "";
										my $tmp_str_source2_t = "";
										my $tmp_str_drain1_t = "";
										my $tmp_str_drain2_t = "";
										my $vName1 = "m".($metal)."r".$row."c".$col;
										my $vName2 = "m".($metal)."r".$row."c".($col+$dist);
										for my $i (0 .. $#{$vedge_out{$vName1}}){ # incoming
											my $toCol = (split /[a-z]/, $virtualEdges[$vedge_out{$vName1}[$i]][1])[3];
											if($toCol == $col && $virtualEdges[$vedge_out{$vName1}[$i]][2] eq $source){
												$tmp_str ="M_$vName1\_$virtualEdges[$vedge_out{$vName1}[$i]][2]";
												$tmp_str_source1 .= " $tmp_str";
											}
											if($toCol == $col && $virtualEdges[$vedge_out{$vName1}[$i]][2] eq $source_s){
												$tmp_str ="M_$vName1\_$virtualEdges[$vedge_out{$vName1}[$i]][2]";
												$tmp_str_source2 .= " $tmp_str";
												$tmp_str_source2_t = $tmp_str;
											}
											if($toCol == $col && $virtualEdges[$vedge_out{$vName1}[$i]][2] eq $drain){
												$tmp_str ="M_$vName1\_$virtualEdges[$vedge_out{$vName1}[$i]][2]";
												$tmp_str_drain1 .= " $tmp_str";
											}
											if($toCol == $col && $virtualEdges[$vedge_out{$vName1}[$i]][2] eq $drain_s){
												$tmp_str ="M_$vName1\_$virtualEdges[$vedge_out{$vName1}[$i]][2]";
												$tmp_str_drain2 .= " $tmp_str";
												$tmp_str_drain2_t = $tmp_str;
											}
										}
										for my $i (0 .. $#{$vedge_out{$vName2}}){ # incoming
											my $toCol = (split /[a-z]/, $virtualEdges[$vedge_out{$vName2}[$i]][1])[3];
											if($toCol == $col+$dist && $virtualEdges[$vedge_out{$vName2}[$i]][2] eq $source){
												$tmp_str ="M_$vName2\_$virtualEdges[$vedge_out{$vName2}[$i]][2]";
												$tmp_str_source1_t = $tmp_str;
											}
											if($toCol == $col+$dist && $virtualEdges[$vedge_out{$vName2}[$i]][2] eq $drain){
												$tmp_str ="M_$vName2\_$virtualEdges[$vedge_out{$vName2}[$i]][2]";
												$tmp_str_drain1_t = $tmp_str;
											}
										}
										if($tmp_str_source1_t ne "" && $tmp_str_source2_t ne ""){
											print $out "(assert (ite (= $tmp_str_source2_t true) (= $tmp_str_source1_t true) (= $tmp_str_source1_t false)))\n";
										}
										if($tmp_str_drain1_t ne "" && $tmp_str_drain2_t ne ""){
											print $out "(assert (ite (= $tmp_str_drain2_t true) (= $tmp_str_drain1_t true) (= $tmp_str_drain1_t false)))\n";
										}
									}
									if($tmp_str_source1 ne "" && $tmp_str_source2 ne "" && $tmp_str_drain1 ne "" && $tmp_str_drain2 ne ""){
										print $out "(assert (= (or$tmp_str_source1) (or$tmp_str_source2)))\n";
										print $out "(assert (= (or$tmp_str_drain1) (or$tmp_str_drain2)))\n";
									}
								}
							}
						}
						$dist++;
					}
				}
			}
			if($tmp[0][$it*$step-1] <= $lastIdxPMOS){
				print $out "(assert (bvuge x$tmp[0][$it*$step-1] (_ bv".($step-1)." $lenV)))\n";
				push(@arr_pmos_fgroup, $tmp[0][$it*$step-1]);
			}
			else{
				print $out "(assert (bvuge x$tmp[0][$it*$step-1] (_ bv".($step-1)." $lenV)))\n";
				push(@arr_nmos_fgroup, $tmp[0][$it*$step-1]);
			}
		}
		if($last_step>0){
			for my $k($step*$it .. $step*$it+$last_step-1){
				my $dist = 1;
				if($k==0 && $tmp[0][0] <= $lastIdxPMOS){
					print $out "(assert (bvule x$tmp[0][0] (_ bv".($numTrackV - $last_step)." $lenV)))\n";
						my $source = $h_instIdx_S{$tmp[0][0]};
						my $gate = $h_instIdx_G{$tmp[0][0]};
						my $drain = $h_instIdx_D{$tmp[0][0]};
						for my $tier (0 .. $numTier-1){
							my $row = $h_track{$tier."_P"};
							for my $metal ($tier*2 .. $tier*2+2){
								my $tmp_str = "";
								for my $col ($numTrackV - $last_step+1.. $numTrackV-1) {
									my $vName1 = "m".($metal)."r".$row."c".$col;
									for my $i (0 .. $#{$vedge_out{$vName1}}){ # incoming
										my $toCol   = (split /[a-z]/, $virtualEdges[$vedge_out{$vName1}[$i]][1])[3];
										if($toCol == $col && ($virtualEdges[$vedge_out{$vName1}[$i]][2] eq $source ||
													$virtualEdges[$vedge_out{$vName1}[$i]][2] eq $gate ||
													$virtualEdges[$vedge_out{$vName1}[$i]][2] eq $drain)){
											$tmp_str ="M_$vName1\_$virtualEdges[$vedge_out{$vName1}[$i]][2]";
											print $out "(assert (= $tmp_str false))\n";
										}
									}
								}
							}
						}
					push(@arr_pmos_group, $tmp[0][0]);
				}
				elsif($k==0){
					print $out "(assert (bvule x$tmp[0][0] (_ bv".($numTrackV - $last_step)." $lenV)))\n";
					my $source = $h_instIdx_S{$tmp[0][0]};
					my $gate = $h_instIdx_G{$tmp[0][0]};
					my $drain = $h_instIdx_D{$tmp[0][0]};
					for my $tier (0 .. $numTier-1){
						my $row = $h_track{$tier."_N"};
						for my $metal ($tier*2 .. $tier*2+2){
							my $tmp_str = "";
							for my $col ($numTrackV - $last_step+1 .. $numTrackV-1) {
								my $vName1 = "m".($metal)."r".$row."c".$col;
								for my $i (0 .. $#{$vedge_out{$vName1}}){ # incoming
									my $toCol   = (split /[a-z]/, $virtualEdges[$vedge_out{$vName1}[$i]][1])[3];
									if($toCol == $col && ($virtualEdges[$vedge_out{$vName1}[$i]][2] eq $source ||
												$virtualEdges[$vedge_out{$vName1}[$i]][2] eq $gate ||
												$virtualEdges[$vedge_out{$vName1}[$i]][2] eq $drain)){
										$tmp_str ="M_$vName1\_$virtualEdges[$vedge_out{$vName1}[$i]][2]";
										print $out "(assert (= $tmp_str false))\n";
									}
								}
							}
						}
					}
					push(@arr_nmos_group, $tmp[0][0]);
				}
				for my $l($step*$it .. $step*$it+$last_step-1){
					if($k>=$l) { next;}
					print $out "(assert (and (= t$tmp[0][$l] t$tmp[0][$k]) (= x$tmp[0][$l] (bvadd x$tmp[0][$k] (_ bv".($dist)." $lenV)))))\n";
					if($k==0){
						print $out "(assert (bvule x$tmp[0][$l] (_ bv".($numTrackV - $last_step+$dist)." $lenV)))\n";
						my $source = $h_instIdx_S{$tmp[0][$l]};
						my $gate = $h_instIdx_G{$tmp[0][$l]};
						my $drain = $h_instIdx_D{$tmp[0][$l]};
						for my $tier (0 .. $numTier-1){
							my $row = -1;
							if($tmp[0][0] <= $lastIdxPMOS){
								$row = $h_track{$tier."_P"};
							}
							else{
								$row = $h_track{$tier."_N"};
							}
							for my $metal ($tier*2 .. $tier*2+2){
								my $tmp_str = "";
								for my $col ($numTrackV - $last_step+1+$dist .. $numTrackV-1) {
									my $vName1 = "m".($metal)."r".$row."c".$col;
									for my $i (0 .. $#{$vedge_out{$vName1}}){ # incoming
										my $toCol   = (split /[a-z]/, $virtualEdges[$vedge_out{$vName1}[$i]][1])[3];
										if($toCol == $col && ($virtualEdges[$vedge_out{$vName1}[$i]][2] eq $source ||
													$virtualEdges[$vedge_out{$vName1}[$i]][2] eq $gate ||
													$virtualEdges[$vedge_out{$vName1}[$i]][2] eq $drain)){
											$tmp_str ="M_$vName1\_$virtualEdges[$vedge_out{$vName1}[$i]][2]";
											print $out "(assert (= $tmp_str false))\n";
										}
									}
								}
								for my $col (0 .. $dist-1) {
									my $vName1 = "m".($metal)."r".$row."c".$col;
									for my $i (0 .. $#{$vedge_out{$vName1}}){ # incoming
										my $toCol   = (split /[a-z]/, $virtualEdges[$vedge_out{$vName1}[$i]][1])[3];
										if($toCol == $col && ($virtualEdges[$vedge_out{$vName1}[$i]][2] eq $source ||
													$virtualEdges[$vedge_out{$vName1}[$i]][2] eq $gate ||
													$virtualEdges[$vedge_out{$vName1}[$i]][2] eq $drain)){
											$tmp_str ="M_$vName1\_$virtualEdges[$vedge_out{$vName1}[$i]][2]";
											print $out "(assert (= $tmp_str false))\n";
										}
									}
								}
							}
						}
					}
					$dist++;
				}
			}
			if($tmp[0][$it*$step+$last_step-1] <= $lastIdxPMOS){
				print $out "(assert (bvuge x$tmp[0][$it*$step+$last_step-1] (_ bv".($last_step-1)." $lenV)))\n";
				push(@arr_pmos_fgroup, $tmp[0][$it*$step+$last_step-1]);
			}
			else{
				print $out "(assert (bvuge x$tmp[0][$it*$step+$last_step-1] (_ bv".($last_step-1)." $lenV)))\n";
				push(@arr_nmos_fgroup, $tmp[0][$it*$step+$last_step-1]);
			}
		}
	}
}
print $out ";Conditional Assignment of inter-routing in the multi-finger FETs\n";
for my $netIndex (0 .. $#nets) {
	for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
		my $inst_pin_s = $h_inst_idx{$pins[$h_pinId_idx{$nets[$netIndex][3]}][4]};
		my $inst_pin_t = $h_inst_idx{$pins[$h_pinId_idx{$nets[$netIndex][5][$commodityIndex]}][4]};
		my $pin_s = $nets[$netIndex][3];
		my $pin_t = $nets[$netIndex][5][$commodityIndex];
		my $dist = -1;
		my $inst_s = -1;
		my $inst_t = -1;

		# Skip If source or sink FETs are Gate nodes
		if($pins[$h_pinId_idx{$nets[$netIndex][3]}][5] eq "G" || $pins[$h_pinId_idx{$nets[$netIndex][5][$commodityIndex]}][5] eq "G"){
			next;
		}
		# Skip If instances of source/sink are not in the same multi-finger FET group
		if(!exists($h_mf_info{"$inst_pin_s\_$inst_pin_t"}) && !exists($h_mf_info{"$inst_pin_t\_$inst_pin_s"})){
			next;
		}
		else{
			if(exists($h_mf_info{"$inst_pin_s\_$inst_pin_t"})){
				$dist = $h_mf_info{"$inst_pin_s\_$inst_pin_t"};
				$inst_s = $inst_pin_s;
				$inst_t = $inst_pin_t;
			}
			else{
				$dist = $h_mf_info{"$inst_pin_t\_$inst_pin_s"};
				$inst_s = $inst_pin_t;
				$inst_t = $inst_pin_s;
				my $tmp = $pin_t;
				$pin_t = $pin_s;
				$pin_s = $tmp;
			}

			for my $tier (0 .. $numTier-1){
				my $row = -1;
				if($inst_s <= $lastIdxPMOS){
					$row = $h_track{$tier."_P"};
				}
				else{
					$row = $h_track{$tier."_N"};
				}
				my $metal = $tier*2;
				for my $col (0 .. $numTrackV - 1-$dist) {
					my $tmp_str = "";
					my $tmp_str2 = "";
					my $vName = "m".($metal)."r".$row."c".$col;
					my $vName2 = "m".($metal)."r".$row."c".($col+$dist);
					for my $i (0 .. $#{$vedge_out{$vName}}){ # incoming
						if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $pin_s){
							$tmp_str ="N$nets[$netIndex][1]\_C$commodityIndex\_E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
							next;
						}
					}
					for my $i (0 .. $#{$vedge_out{$vName2}}){ # incoming
						if($virtualEdges[$vedge_out{$vName2}[$i]][2] eq $pin_t){
							$tmp_str2 ="N$nets[$netIndex][1]\_C$commodityIndex\_E_$vName2\_$virtualEdges[$vedge_out{$vName2}[$i]][2]";
							next;
						}
					}
					my %h_tmp = ();
					print $out "(assert (ite (= $tmp_str true) (and (= $tmp_str2 true)";
					for my $i(1 .. $dist){
						my $vName_r = $vertices{$vName}[5][1];
						$tmp_str ="N$nets[$netIndex][1]\_C$commodityIndex\_E_$vName\_$vName_r";
						print $out " (= $tmp_str true)";
						$h_tmp{$tmp_str} = 1;
						$vName = $vertices{$vName}[5][1];
					}
					for my $udeIndex (0 .. $#udEdges) {
						if(!exists($h_tmp{"N$nets[$netIndex][1]\_C$commodityIndex\_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2]"})){
							print $out " (= N$nets[$netIndex][1]\_C$commodityIndex\_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] false)";
						}
					}
					print $out ") (= true true)";
					print $out "))\n";
				}
			}
		}
	}
}

print $out ";Unset All Metal/Net/Wire over the rightmost cell/metal(>COST_SIZE)\n";
# Unset All Metal/Net/Wire over the rightmost cell/metal(>COST_SIZE)
for my $udeIndex (0 .. $#udEdges) {
	my $toCol   = (split /[a-z]/, $udEdges[$udeIndex][2])[3];
	print $out "(assert (ite (bvult COST_SIZE (_ bv".($toCol)." $lenV)) (= M_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] false) (= true true)))\n";
}
for my $netIndex (0 .. $#nets) {
	for my $udeIndex (0 .. $#udEdges) {
		my $toCol   = (split /[a-z]/, $udEdges[$udeIndex][2])[3];
		print $out "(assert (ite (bvult COST_SIZE (_ bv".($toCol)." $lenV)) (= N$nets[$netIndex][1]\_";
		print $out "E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] false) (= true true)))\n";
	}
}
for my $netIndex (0 .. $#nets) {
	for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
		for my $udeIndex (0 .. $#udEdges) {
			my $toCol   = (split /[a-z]/, $udEdges[$udeIndex][2])[3];
			print $out "(assert (ite (bvult COST_SIZE (_ bv".($toCol)." $lenV)) (= N$nets[$netIndex][1]\_";
			print $out "C$commodityIndex\_";
			print $out "E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] false) (= true true)))\n";
		}
	}
}
for my $vEdgeIndex (0 .. $#virtualEdges) {
	my $toCol   = (split /[a-z]/, $virtualEdges[$vEdgeIndex][1])[3];
	print $out "(assert (ite (bvult COST_SIZE (_ bv".($toCol)." $lenV)) (= M_$virtualEdges[$vEdgeIndex][1]_$virtualEdges[$vEdgeIndex][2] false) (= true true)))\n";
}
for my $netIndex (0 .. $#nets) {
	for my $vEdgeIndex (0 .. $#virtualEdges) {
		my $toCol   = (split /[a-z]/, $virtualEdges[$vEdgeIndex][1])[3];
		if($virtualEdges[$vEdgeIndex][2] eq $nets[$netIndex][3]){
			print $out "(assert (ite (bvult COST_SIZE (_ bv".($toCol)." $lenV)) (= N$nets[$netIndex][1]_E_$virtualEdges[$vEdgeIndex][1]_$virtualEdges[$vEdgeIndex][2] false) (= true true)))\n";
		}
		else{
			for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
				if($virtualEdges[$vEdgeIndex][2] eq $nets[$netIndex][5][$commodityIndex]){
					print $out "(assert (ite (bvult COST_SIZE (_ bv".($toCol)." $lenV)) (= N$nets[$netIndex][1]_E_$virtualEdges[$vEdgeIndex][1]_$virtualEdges[$vEdgeIndex][2] false) (= true true)))\n";
				}
			}
		}
	}
}
for my $netIndex (0 .. $#nets) {
	for my $vEdgeIndex (0 .. $#virtualEdges) {
		my $toCol   = (split /[a-z]/, $virtualEdges[$vEdgeIndex][1])[3];
		for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
			if($virtualEdges[$vEdgeIndex][2] eq $nets[$netIndex][3]){
				print $out "(assert (ite (bvult COST_SIZE (_ bv".($toCol)." $lenV)) (= N$nets[$netIndex][1]_C$commodityIndex\_E_$virtualEdges[$vEdgeIndex][1]_$virtualEdges[$vEdgeIndex][2] false) (= true true)))\n";
			}
			if($virtualEdges[$vEdgeIndex][2] eq $nets[$netIndex][5][$commodityIndex]){
				print $out "(assert (ite (bvult COST_SIZE (_ bv".($toCol)." $lenV)) (= N$nets[$netIndex][1]_C$commodityIndex\_E_$virtualEdges[$vEdgeIndex][1]_$virtualEdges[$vEdgeIndex][2] false) (= true true)))\n";
			}
		}
	}
}

if($BS == 1){
	print $out ";Removing Symmetric Placement Cases\n";
	my $numPMOS = scalar(@arr_pmos_group);
	my $numNMOS = scalar(@arr_nmos_group);

	if($numPMOS<=1 && $numNMOS <=1){
		print "NO BS applied\n"
	}
	else{
		my @arr_pmos = @arr_pmos_group;
		my @arr_nmos = @arr_nmos_group;

		my @comb_l_pmos = ();
		my @comb_l_nmos = ();
		my @comb_c_pmos = ();
		my @comb_c_nmos = ();
		my @comb_r_pmos = ();
		my @comb_r_nmos = ();

		if($numPMOS % 2 == 0){
			my @tmp_comb_l_pmos = combine([@arr_pmos],$numPMOS/2);
			for my $i(0 .. $#tmp_comb_l_pmos){
				my @tmp_comb = ();
				my $isComb = 0;
				for my $j(0 .. $numPMOS-1){
					for my $k(0 .. $#{$tmp_comb_l_pmos[$i]}){
						if($tmp_comb_l_pmos[$i][$k] == $arr_pmos_group[$j]){
							$isComb = 1;
							last;
						}
					}
					if($isComb == 0){
						push(@tmp_comb, $arr_pmos_group[$j]);
					}
					$isComb = 0;
				}
				push(@comb_l_pmos, $tmp_comb_l_pmos[$i]);
				push(@comb_r_pmos, [@tmp_comb]);
				if($#tmp_comb_l_pmos == 1){
					last;
				}
			}
		}
		else{
			for my $m(0 .. $numPMOS - 1){
				@arr_pmos = ();
				for my $i (0 .. $numPMOS - 1){
					if($i!=$m){
						push(@arr_pmos, $arr_pmos_group[$i]);
					}
				}
				my @tmp_comb_l_pmos = combine([@arr_pmos],($numPMOS-1)/2);
				for my $i(0 .. $#tmp_comb_l_pmos){
					my @tmp_comb = ();
					my $isComb = 0;
					for my $j(0 .. $numPMOS-1){
						for my $k(0 .. $#{$tmp_comb_l_pmos[$i]}){
							if($tmp_comb_l_pmos[$i][$k] == $arr_pmos_group[$j] || $arr_pmos_group[$j] == $arr_pmos_group[$m]){
								$isComb = 1;
								last;
							}
						}
						if($isComb == 0){
							push(@tmp_comb, $arr_pmos_group[$j]);
						}
						$isComb = 0;
					}
					push(@comb_l_pmos, $tmp_comb_l_pmos[$i]);
					push(@comb_r_pmos, [@tmp_comb]);
					push(@comb_c_pmos, [($arr_pmos_group[$m])]);
					if($#tmp_comb_l_pmos == 1){
						last;
					}
				}
			}
		}
		for my $i(0 .. $#comb_l_pmos){
			print $out "(assert (or";
			for my $l(0 .. $#{$comb_l_pmos[$i]}){
				for my $m(0 .. $#{$comb_r_pmos[$i]}){
					print $out " (bvule x$comb_l_pmos[$i][$l] x$comb_r_pmos[$i][$m])";
					for my $n(0 .. $#{$comb_c_pmos[$i]}){
						print $out " (bvule x$comb_l_pmos[$i][$l] x$comb_c_pmos[$i][$n])";
						print $out " (bvuge x$comb_r_pmos[$i][$m] x$comb_c_pmos[$i][$n])";
					}
				}
			}
			print $out "))\n";
		}
	}
}
print $out ";Prevent Non-Power Nets routing on power rails\n";
for my $netIndex (0 .. $#nets) {
	for my $udeIndex (0 .. $#udEdges) {
		my $fromCol = (split /[a-z]/, $udEdges[$udeIndex][1])[3]; # 1:metal 2:row 3:col
		my $toCol   = (split /[a-z]/, $udEdges[$udeIndex][2])[3];
		my $fromRow = (split /[a-z]/, $udEdges[$udeIndex][1])[2]; # 1:metal 2:row 3:col
		my $toRow   = (split /[a-z]/, $udEdges[$udeIndex][2])[2];
		my $fromMetal = (split /[a-z]/, $udEdges[$udeIndex][1])[1]; # 1:metal 2:row 3:col
		my $toMetal = (split /[a-z]/, $udEdges[$udeIndex][2])[1];
		if(!($nets[$netIndex][1] == $netVDD || $nets[$netIndex][1] == $netVSS)){
			if($fromRow == 0 || $toRow == $numTrackH-1){
				print $out "(assert (= N$nets[$netIndex][1]_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] false))\n";
				for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
					print $out "(assert (= N$nets[$netIndex][1]_C$commodityIndex\_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] false))\n";
				}
			}
		}
	}
}
print $out ";Enable net/metal segment of power nets on power rails\n";
for my $netIndex (0 .. $#nets) {
	for my $udeIndex (0 .. $#udEdges) {
		my $fromCol = (split /[a-z]/, $udEdges[$udeIndex][1])[3]; # 1:metal 2:row 3:col
		my $toCol   = (split /[a-z]/, $udEdges[$udeIndex][2])[3];
		my $fromRow = (split /[a-z]/, $udEdges[$udeIndex][1])[2]; # 1:metal 2:row 3:col
		my $toRow   = (split /[a-z]/, $udEdges[$udeIndex][2])[2];
		my $fromMetal = (split /[a-z]/, $udEdges[$udeIndex][1])[1]; # 1:metal 2:row 3:col
		my $toMetal = (split /[a-z]/, $udEdges[$udeIndex][2])[1];
		if($nets[$netIndex][1] == $netVDD){
			if(($fromRow == 0 && $toRow == 0)){
				print $out "(assert (ite (bvuge COST_SIZE (_ bv$toCol $lenV)) (= N$nets[$netIndex][1]_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] true) (= N$nets[$netIndex][1]_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] false)))\n";
				print $out "(assert (ite (bvuge COST_SIZE (_ bv$toCol $lenV)) (= M_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] true) (= M_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] false)))\n";
				$h_preassign{"M_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2]"} = 1;
			}
		}
		elsif($nets[$netIndex][1] == $netVSS){
			if(($fromRow == $numTrackH-1 && $toRow == $numTrackH-1)){
				print $out "(assert (ite (bvuge COST_SIZE (_ bv$toCol $lenV)) (= N$nets[$netIndex][1]_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] true) (= N$nets[$netIndex][1]_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] false)))\n";
				print $out "(assert (ite (bvuge COST_SIZE (_ bv$toCol $lenV)) (= M_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] true) (= M_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] false)))\n";
				$h_preassign{"M_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2]"} = 1;
			}
		}
	}
}
print $out ";Disable net/metal segment of power nets on opposite half grids\n";
for my $netIndex (0 .. $#nets) {
	for my $udeIndex (0 .. $#udEdges) {
		my $fromCol = (split /[a-z]/, $udEdges[$udeIndex][1])[3]; # 1:metal 2:row 3:col
		my $toCol   = (split /[a-z]/, $udEdges[$udeIndex][2])[3];
		my $fromRow = (split /[a-z]/, $udEdges[$udeIndex][1])[2]; # 1:metal 2:row 3:col
		my $toRow   = (split /[a-z]/, $udEdges[$udeIndex][2])[2];
		my $fromMetal = (split /[a-z]/, $udEdges[$udeIndex][1])[1]; # 1:metal 2:row 3:col
		my $toMetal = (split /[a-z]/, $udEdges[$udeIndex][2])[1];
		my $half = int($numTrackH/2);
		if($nets[$netIndex][1] == $netVDD){
			if($fromRow>=$half && $toRow>=$half){
				print $out "(assert (= N$nets[$netIndex][1]_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] false))\n";
			}
		}
		elsif($nets[$netIndex][1] == $netVSS){
			if($fromRow<=$half && $toRow<=$half){
				print $out "(assert (= N$nets[$netIndex][1]_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] false))\n";
			}
		}
	}
}
if($CP == 1){
	print $out ";Set Partition Constraints\n";
	# Lower Group => Right Side
	for my $i(0 .. $#inst_group_p-1){
		my $minBound = 1;
		my $maxBound = $numTrackV;
		# PMOS
		for my $j($i+1 .. $#inst_group_p){
			for my $k(0 .. $#{$inst_group_p[$i][1]}){
				for my $l(0 .. $#{$inst_group_p[$j][1]}){
					print $out "(assert (bvuge x$inst_group_p[$i][1][$k] x$inst_group_p[$j][1][$l]))\n";
				}
			}
			$minBound+=$inst_group_p[$j][2];
		}
		for my $j(0 .. $i-1){
			$maxBound-=$inst_group_p[$j][2];
		}
		for my $k(0 .. $#{$inst_group_p[$i][1]}){
			print $out ";(assert (bvuge x$inst_group_p[$i][1][$k] (_ bv$minBound $lenV)))\n";
			print $out ";(assert (bvule x$inst_group_p[$i][1][$k] (_ bv$maxBound $lenV)))\n";
		}
	}
	for my $i(0 .. $#inst_group_n-1){
		my $minBound = 1;
		my $maxBound = $numTrackV;
		# NMOS
		for my $j($i+1 .. $#inst_group_n){
			for my $k(0 .. $#{$inst_group_n[$i][1]}){
				for my $l(0 .. $#{$inst_group_n[$j][1]}){
					print $out "(assert (bvuge x$inst_group_n[$i][1][$k] x$inst_group_n[$j][1][$l]))\n";
				}
			}
			$minBound+=$inst_group_n[$j][2];
		}
		for my $j(0 .. $i-1){
			$maxBound-=$inst_group_n[$j][2];
		}
		for my $k(0 .. $#{$inst_group_n[$i][1]}){
			print $out ";(assert (bvuge x$inst_group_n[$i][1][$k] (_ bv$minBound $lenV)))\n";
			print $out ";(assert (bvule x$inst_group_n[$i][1][$k] (_ bv$maxBound $lenV)))\n";
		}
	}
	print $out ";End of Partition Constraints\n";
}
print $out ";Prevent connection to/from dummy FET's gate nodes on M0/M1 or M3/M4 layers\n";
if($numTier > 1){
	for my $j (0 .. $numTrackV-1) {
		#PFET
		# from dummy gate to gate metal layer
		for my $tier (0 .. $numTier-1){
			print $out "(assert (ite (and (= (or";
			for my $pinIndex (0 .. $#pins) {
				if($pins[$pinIndex][5] eq "G"){
					my $vName = $pins[$pinIndex][0];
					for my $i (0 .. $#{$vedge_in{$vName}}){ # incoming
						my $metal = (split /[a-z]/, $virtualEdges[$vedge_in{$vName}[$i]][1])[1]; # 1:metal 2:row 3:col
						my $row = (split /[a-z]/, $virtualEdges[$vedge_in{$vName}[$i]][1])[2]; # 1:metal 2:row 3:col
						my $col = (split /[a-z]/, $virtualEdges[$vedge_in{$vName}[$i]][1])[3]; # 1:metal 2:row 3:col
						if($row == $h_track{$tier."_P"} && $col == $j && $metal == ($tier*2+1)){
							print $out " M_$virtualEdges[$vedge_in{$vName}[$i]][1]\_$vName";
						}
					}
				}
			}
			print $out ") false) (= (or";
			for my $pinIndex (0 .. $#pins) {
				if($pins[$pinIndex][5] eq "G"){
					my $vName = $pins[$pinIndex][0];
					for my $i (0 .. $#{$vedge_in{$vName}}){ # incoming
						my $metal = (split /[a-z]/, $virtualEdges[$vedge_in{$vName}[$i]][1])[1]; # 1:metal 2:row 3:col
						my $row = (split /[a-z]/, $virtualEdges[$vedge_in{$vName}[$i]][1])[2]; # 1:metal 2:row 3:col
						my $col = (split /[a-z]/, $virtualEdges[$vedge_in{$vName}[$i]][1])[3]; # 1:metal 2:row 3:col
						if($row == $h_track{$tier."_P"} && $col == $j && $metal != ($tier*2+1)){
							print $out " M_$virtualEdges[$vedge_in{$vName}[$i]][1]\_$vName";
						}
					}
				}
			}
			print $out ") true)) (and";
			for my $netIndex (0 .. $#nets) {
				for my $udeIndex (0 .. $#udEdges) {
					my $fromCol = (split /[a-z]/, $udEdges[$udeIndex][1])[3]; # 1:metal 2:row 3:col
					my $toCol   = (split /[a-z]/, $udEdges[$udeIndex][2])[3];
					my $fromRow = (split /[a-z]/, $udEdges[$udeIndex][1])[2]; # 1:metal 2:row 3:col
					my $toRow   = (split /[a-z]/, $udEdges[$udeIndex][2])[2];
					my $fromMetal = (split /[a-z]/, $udEdges[$udeIndex][1])[1]; # 1:metal 2:row 3:col
					my $toMetal = (split /[a-z]/, $udEdges[$udeIndex][2])[1];
					if(($toMetal == $tier*2+1) && ($fromRow == $h_track{$tier."_P"} || $toRow == $h_track{$tier."_P"}) 
						&& ($fromCol == $j || $toCol == $j)){
						print $out " (= N$nets[$netIndex][1]_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] false)";
						for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
							print $out " (= N$nets[$netIndex][1]_C$commodityIndex\_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] false)";
						}
					}
				}
			}
			print $out ") (= true true)))\n";
		}
		#NFET
		# from dummy gate to gate metal layer
		for my $tier (0 .. $numTier-1){
			print $out "(assert (ite (and (= (or";
			for my $pinIndex (0 .. $#pins) {
				if($pins[$pinIndex][5] eq "G"){
					my $vName = $pins[$pinIndex][0];
					for my $i (0 .. $#{$vedge_in{$vName}}){ # incoming
						my $metal = (split /[a-z]/, $virtualEdges[$vedge_in{$vName}[$i]][1])[1]; # 1:metal 2:row 3:col
						my $row = (split /[a-z]/, $virtualEdges[$vedge_in{$vName}[$i]][1])[2]; # 1:metal 2:row 3:col
						my $col = (split /[a-z]/, $virtualEdges[$vedge_in{$vName}[$i]][1])[3]; # 1:metal 2:row 3:col
						if($row == $h_track{$tier."_N"} && $col == $j && $metal == ($tier*2+1)){
							print $out " M_$virtualEdges[$vedge_in{$vName}[$i]][1]\_$vName";
						}
					}
				}
			}
			print $out ") false) (= (or";
			for my $pinIndex (0 .. $#pins) {
				if($pins[$pinIndex][5] eq "G"){
					my $vName = $pins[$pinIndex][0];
					for my $i (0 .. $#{$vedge_in{$vName}}){ # incoming
						my $metal = (split /[a-z]/, $virtualEdges[$vedge_in{$vName}[$i]][1])[1]; # 1:metal 2:row 3:col
						my $row = (split /[a-z]/, $virtualEdges[$vedge_in{$vName}[$i]][1])[2]; # 1:metal 2:row 3:col
						my $col = (split /[a-z]/, $virtualEdges[$vedge_in{$vName}[$i]][1])[3]; # 1:metal 2:row 3:col
						if($row == $h_track{$tier."_N"} && $col == $j && $metal != ($tier*2+1)){
							print $out " M_$virtualEdges[$vedge_in{$vName}[$i]][1]\_$vName";
						}
					}
				}
			}
			print $out ") true)) (and";
			for my $netIndex (0 .. $#nets) {
				for my $udeIndex (0 .. $#udEdges) {
					my $fromCol = (split /[a-z]/, $udEdges[$udeIndex][1])[3]; # 1:metal 2:row 3:col
					my $toCol   = (split /[a-z]/, $udEdges[$udeIndex][2])[3];
					my $fromRow = (split /[a-z]/, $udEdges[$udeIndex][1])[2]; # 1:metal 2:row 3:col
					my $toRow   = (split /[a-z]/, $udEdges[$udeIndex][2])[2];
					my $fromMetal = (split /[a-z]/, $udEdges[$udeIndex][1])[1]; # 1:metal 2:row 3:col
					my $toMetal = (split /[a-z]/, $udEdges[$udeIndex][2])[1];
					if(($toMetal == $tier*2+1) && ($fromRow == $h_track{$tier."_N"} || $toRow == $h_track{$tier."_N"}) 
						&& ($fromCol == $j || $toCol == $j)){
						print $out " (= N$nets[$netIndex][1]_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] false)";
						for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
							print $out " (= N$nets[$netIndex][1]_C$commodityIndex\_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] false)";
						}
					}
				}
			}
			print $out ") (= true true)))\n";
		}
	}
}
print $out ";pre-restrict the assignement of un-connected FETs on the same column\n";
if($numTier >= 2){
	for my $i (0 .. $lastIdxPMOS) {
		for my $j (0 .. $lastIdxPMOS) {
			if($i >= $j) { next;}
			my $s_i = $h_instIdx_S{$i};
			my $d_i = $h_instIdx_D{$i};
			my $s_j = $h_instIdx_S{$j};
			my $d_j = $h_instIdx_D{$j};
			my $n_s_i = $h_netName_idx{$pins[$h_pinId_idx{$s_i}][1]};
			my $n_d_i = $h_netName_idx{$pins[$h_pinId_idx{$d_i}][1]};
			my $n_s_j = $h_netName_idx{$pins[$h_pinId_idx{$s_j}][1]};
			my $n_d_j = $h_netName_idx{$pins[$h_pinId_idx{$d_j}][1]};
			if(($n_s_i != $n_s_j) && ($n_s_i != $n_d_j) && ($n_d_i != $n_s_j) && ($n_d_i != $n_d_j)){
				if($numTier  == 2){
					print $out "(assert (or (bvult x$i x$j) (bvugt x$i x$j)))\n";
				}
				else{
					print $out "(assert (ite (or (= t$i (bvadd t$j (_ bv1 $lenT))) (= t$j (bvadd t$i (_ bv1 $lenT)))) (or (bvult x$i x$j) (bvugt x$i x$j)) (= true true)))\n";
				}
			}	
		}
	}
	for my $i ($lastIdxPMOS + 1 .. $numInstance - 1) {
		for my $j ($lastIdxPMOS + 1 .. $numInstance - 1) {
			if($i >= $j) { next;}
			my $s_i = $h_instIdx_S{$i};
			my $d_i = $h_instIdx_D{$i};
			my $s_j = $h_instIdx_S{$j};
			my $d_j = $h_instIdx_D{$j};
			my $n_s_i = $h_netName_idx{$pins[$h_pinId_idx{$s_i}][1]};
			my $n_d_i = $h_netName_idx{$pins[$h_pinId_idx{$d_i}][1]};
			my $n_s_j = $h_netName_idx{$pins[$h_pinId_idx{$s_j}][1]};
			my $n_d_j = $h_netName_idx{$pins[$h_pinId_idx{$d_j}][1]};
			if($n_s_i != $n_s_j && $n_s_i != $n_d_j && $n_d_i != $n_s_j && $n_d_i != $n_d_j){
				if($numTier  == 2){
					print $out "(assert (or (bvult x$i x$j) (bvugt x$i x$j)))\n";
				}
				else{
					print $out "(assert (ite (or (= t$i (bvadd t$j (_ bv1 $lenT))) (= t$j (bvadd t$i (_ bv1 $lenT)))) (or (bvult x$i x$j) (bvugt x$i x$j)) (= true true)))\n";
				}
			}	
		}
	}
}
print $out ";Initial Assignment for S/G/D pins of P/N FET in the same column/tier with the same netid between different instances in the same P/N region\n";
if($numTier >= 2){
	for my $netIndex (0 .. $#nets) {
		for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
			my $inst_pin_s = $h_inst_idx{$pins[$h_pinId_idx{$nets[$netIndex][3]}][4]};
			my $inst_pin_t = $h_inst_idx{$pins[$h_pinId_idx{$nets[$netIndex][5][$commodityIndex]}][4]};
			my $pin_s = $nets[$netIndex][3];
			my $pin_t = $nets[$netIndex][5][$commodityIndex];

			# Skip If source/sink FETs are in the different region
			if(!(($inst_pin_s <= $lastIdxPMOS && $inst_pin_t <= $lastIdxPMOS) || ($inst_pin_s > $lastIdxPMOS && $inst_pin_t > $lastIdxPMOS))){
				next;
			}
			# Skip If source/sink FETs are Gate Type
			if($pins[$h_pinId_idx{$nets[$netIndex][3]}][5] eq "G" || $pins[$h_pinId_idx{$nets[$netIndex][5][$commodityIndex]}][5] eq "G"){
				next;
			}
			# Skip If Sink node is extenal pin
			if($nets[$netIndex][5][$commodityIndex] eq $keySON || $nets[$netIndex][5][$commodityIndex] eq $keySON_VDD || $nets[$netIndex][5][$commodityIndex] eq $keySON_VSS){
				next;
			}
			for my $tier (1 .. $numTier-1){
				my $metal = $tier*2;
				my $row = -1;
				if($inst_pin_s <= $lastIdxPMOS){ 
					$row = $h_track{$tier."_P"};
				}
				else{
					$row = $h_track{$tier."_N"};
				}
				for my $col (0 .. $numTrackV-1){
					my $vName = "m".($metal)."r".$row."c".$col;
					print $out "(assert (ite (and";
					for my $i (0 .. $#{$vedge_out{$vName}}){ # incoming
						my $tmp_str = "";
						if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $pin_s){
							$tmp_str ="N$nets[$netIndex][1]\_C$commodityIndex\_E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
							print $out " (= $tmp_str true)";
						}
						if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $pin_t){
							$tmp_str ="N$nets[$netIndex][1]\_C$commodityIndex\_E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
							print $out " (= $tmp_str true)";
						}
					}
					print $out ") (and";
					for my $udeIndex (0 .. $#udEdges) {
						print $out " (= N$nets[$netIndex][1]\_C$commodityIndex\_E_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] false)";
					}
					print $out ") (= true true)))\n";
				}
			}
		}
	}
}
print $out ";Initial Assignment for S/G/D pins of P/N FET in the same column/tier with the same netid between different P/N region\n";
for my $netIndex (0 .. $#nets) {
	for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
		my $inst_pin_s = $h_inst_idx{$pins[$h_pinId_idx{$nets[$netIndex][3]}][4]};
		my $inst_pin_t = $h_inst_idx{$pins[$h_pinId_idx{$nets[$netIndex][5][$commodityIndex]}][4]};
		my $pin_s = $nets[$netIndex][3];
		my $pin_t = $nets[$netIndex][5][$commodityIndex];

		# Skip If source/sink FETs are in the same region
		if(($inst_pin_s <= $lastIdxPMOS && $inst_pin_t <= $lastIdxPMOS) || ($inst_pin_s > $lastIdxPMOS && $inst_pin_t > $lastIdxPMOS)){
			next;
		}
		# Skip If source/sink FETs have different type : G <> S/D
		if($pins[$h_pinId_idx{$nets[$netIndex][3]}][5] eq "G" && $pins[$h_pinId_idx{$nets[$netIndex][5][$commodityIndex]}][5] ne "G"){
			next;
		}
		elsif($pins[$h_pinId_idx{$nets[$netIndex][3]}][5] ne "G" && $pins[$h_pinId_idx{$nets[$netIndex][5][$commodityIndex]}][5] eq "G"){
			next;
		}
		# Skip If Sink node is extenal pin
		if($nets[$netIndex][5][$commodityIndex] eq $keySON || $nets[$netIndex][5][$commodityIndex] eq $keySON_VDD || $nets[$netIndex][5][$commodityIndex] eq $keySON_VSS){
			next;
		}
		for my $tier (0 .. $numTier-1){
			my $row_s = -1;
			my $row_t = -1;
			if($inst_pin_s <= $lastIdxPMOS){ 
				$row_s = $h_track{$tier."_P"};
				$row_t = $h_track{$tier."_N"};
			}
			else{
				$row_s = $h_track{$tier."_N"};
				$row_t = $h_track{$tier."_P"};
			}

			for my $col (0 .. $numTrackV-1){
				my $metal = -1;
				my %h_tmp = ();
				if($pins[$h_pinId_idx{$nets[$netIndex][3]}][5] eq "G"){
					print $out "(assert (ite (and (= t$inst_pin_s t$inst_pin_t) (= t$inst_pin_s (_ bv$tier $lenT)) (= x$inst_pin_s x$inst_pin_t) (= x$inst_pin_s (_ bv$col $lenV)))";
					$metal = $tier*2 + 1;
					print $out " (and";
					for my $row ($h_track{$tier."_P"} .. $h_track{$tier."_N"}-1){
						my $vName_1 = "m".$metal."r".$row."c".$col;
						my $vName_2 = "m".$metal."r".($row+1)."c".$col;
						my $tmp_vname = "N$nets[$netIndex][1]_C$commodityIndex\_E_$vName_1\_$vName_2";
						$h_tmp{$tmp_vname} = 1;
						print $out " (= $tmp_vname true)";
					}
					for my $col2 (0 .. $numTrackV-1){
						for my $row2 (0 .. $numTrackH-1) {
							for my $metal2 (0 .. $numMetalLayer-1) { 
								my $vName = "m".$metal2."r".$row2."c".$col2;
								for my $i (0 .. $#{$edge_in{$vName}}){ # incoming
									my $tmp_vname = "N$nets[$netIndex][1]_C$commodityIndex\_E_$udEdges[$edge_in{$vName}[$i]][1]_$vName";
									if(!exists($h_tmp{$tmp_vname})){
										print $out " (= $tmp_vname false)";
									}
								}
								for my $i (0 .. $#{$edge_out{$vName}}){ # incoming
									my $tmp_vname = "N$nets[$netIndex][1]_C$commodityIndex\_E_$vName\_$udEdges[$edge_out{$vName}[$i]][2]";
									if(!exists($h_tmp{$tmp_vname})){
										print $out " (= $tmp_vname false)";
									}
								}
							}
						}
					}
					print $out ") (= true true)))\n";
				}
				else{
					for my $m (0 .. 1){
						%h_tmp = ();
						if($tier>0 && $m == 0){
							next;
						}
						elsif($tier==0 && $m == 0){
							$metal = 0;
						}
						else{
							$metal = ($tier+1)*2;
						}
						my $vName_s = "m".$metal."r".$row_s."c".$col;
						my $vName_t = "m".$metal."r".$row_t."c".$col;
						my $tmp_vName_s = "N$nets[$netIndex][1]_C$commodityIndex\_E_$vName_s\_$pin_s";
						my $tmp_vName_t = "N$nets[$netIndex][1]_C$commodityIndex\_E_$vName_t\_$pin_t";
						print $out "(assert (ite (and (= t$inst_pin_s t$inst_pin_t) (= t$inst_pin_s (_ bv$tier $lenT)) ";
						print $out "(= x$inst_pin_s x$inst_pin_t) (= x$inst_pin_s (_ bv$col $lenV)) ";
						print $out "(= $tmp_vName_s true) (= $tmp_vName_t true))";
						print $out " (and";
						for my $row ($h_track{$tier."_P"} .. $h_track{$tier."_N"}-1){
							my $vName_1 = "m".$metal."r".$row."c".$col;
							my $vName_2 = "m".$metal."r".($row+1)."c".$col;
							my $tmp_vname = "N$nets[$netIndex][1]_C$commodityIndex\_E_$vName_1\_$vName_2";
							$h_tmp{$tmp_vname} = 1;
							print $out " (= $tmp_vname true)";
						}
						for my $col2 (0 .. $numTrackV-1){
							for my $row2 (0 .. $numTrackH-1) {
								for my $metal2 (0 .. $numMetalLayer-1) { 
									my $vName = "m".$metal2."r".$row2."c".$col2;
									for my $i (0 .. $#{$edge_in{$vName}}){ # incoming
										my $tmp_vname = "N$nets[$netIndex][1]_C$commodityIndex\_E_$udEdges[$edge_in{$vName}[$i]][1]_$vName";
										if(!exists($h_tmp{$tmp_vname})){
											print $out " (= $tmp_vname false)";
										}
									}
									for my $i (0 .. $#{$edge_out{$vName}}){ # incoming
										my $tmp_vname = "N$nets[$netIndex][1]_C$commodityIndex\_E_$vName\_$udEdges[$edge_out{$vName}[$i]][2]";
										if(!exists($h_tmp{$tmp_vname})){
											print $out " (= $tmp_vname false)";
										}
									}
								}
							}
						}
						print $out ") (= true true)))\n";
					}
				}
			}
		}


	}
}

if($LC == 1){
	print $out ";Localization.\n\n";
	print $out ";Conditional Localization for All Commodities\n\n";
	for my $netIndex (0 .. $#nets) {
		for my $commodityIndex (0 .. $nets[$netIndex][4]-1) {
			my $inst_pin_s = $h_inst_idx{$pins[$h_pinId_idx{$nets[$netIndex][3]}][4]};
			my $inst_pin_t = $h_inst_idx{$pins[$h_pinId_idx{$nets[$netIndex][5][$commodityIndex]}][4]};
			my $pidx_s = $nets[$netIndex][3];
			my $pidx_t = $nets[$netIndex][5][$commodityIndex];
			$pidx_s =~ s/pin\S+_(\d+)/\1/g;
			$pidx_t =~ s/pin\S+_(\d+)/\1/g;
			my %h_edge = ();
			my $tmp_str = "";
			if($nets[$netIndex][5][$commodityIndex] ne $keySON && $nets[$netIndex][5][$commodityIndex] ne $keySON_VDD && $nets[$netIndex][5][$commodityIndex] ne $keySON_VSS){
				for my $col (0 .. $numTrackV-1){
					print $out "(assert (ite (bvuge x$inst_pin_s x$inst_pin_t)\n";
					print $out "             (and (ite (bvult x$inst_pin_s (_ bv".($col-$LT>=0?($col-$LT):(0))." $lenV)) (and"; 
					%h_edge = ();
					for my $row (0 .. $numTrackH-1) {
						for my $metal (0 .. $numMetalLayer-1) { 
							my $vName = "m".$metal."r".$row."c".$col;
							for my $i (0 .. $#{$edge_in{$vName}}){ # incoming
								if(!exists($h_edge{"$udEdges[$edge_in{$vName}[$i]][1]_$vName"})){
									print $out " (= ";
									print $out "N$nets[$netIndex][1]\_";
									print $out "C$commodityIndex\_";
									print $out "E_$udEdges[$edge_in{$vName}[$i]][1]_$vName";
									print $out " false)";
									$h_edge{"$udEdges[$edge_in{$vName}[$i]][1]_$vName"} = 1;
								}
							}
							for my $i (0 .. $#{$edge_out{$vName}}){ # incoming
								if(!exists($h_edge{"$vName\_$udEdges[$edge_out{$vName}[$i]][2]"})){
									print $out " (= ";
									print $out "N$nets[$netIndex][1]\_";
									print $out "C$commodityIndex\_";
									print $out "E_$vName\_$udEdges[$edge_out{$vName}[$i]][2]";
									print $out " false)";
									$h_edge{"$vName\_$udEdges[$edge_out{$vName}[$i]][2]"} = 1;
								}
							}
							for my $i (0 .. $#{$vedge_out{$vName}}){ # sink
								if(!exists($h_edge{"$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]"})){
									if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][3] || $virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][5][$commodityIndex]){
										$tmp_str ="N$nets[$netIndex][1]\_";
										$tmp_str.="C$commodityIndex\_";
										$tmp_str.="E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
										print $out " (= ";
										print $out $tmp_str;
										print $out " false)";
										$h_edge{"$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]"} = 1;
									}
								}
							}
						}
					}
					print $out ") (= true true))\n";
					print $out "                  (ite (bvugt x$inst_pin_t (_ bv".($col+$LT>=$numTrackV-1?($numTrackV-1):($col+$LT>=0?($col+$LT):(0)))." $lenV)) (and"; 
					%h_edge = ();
					for my $row (0 .. $numTrackH-1) {
						for my $metal (0 .. $numMetalLayer-1) { 
							my $vName = "m".$metal."r".$row."c".$col;
							for my $i (0 .. $#{$edge_in{$vName}}){ # incoming
								if(!exists($h_edge{"$udEdges[$edge_in{$vName}[$i]][1]_$vName"})){
									print $out " (= ";
									print $out "N$nets[$netIndex][1]\_";
									print $out "C$commodityIndex\_";
									print $out "E_$udEdges[$edge_in{$vName}[$i]][1]_$vName";
									print $out " false)";
									$h_edge{"$udEdges[$edge_in{$vName}[$i]][1]_$vName"} = 1;
								}
							}
							for my $i (0 .. $#{$edge_out{$vName}}){ # incoming
								if(!exists($h_edge{"$vName\_$udEdges[$edge_out{$vName}[$i]][2]"})){
									print $out " (= ";
									print $out "N$nets[$netIndex][1]\_";
									print $out "C$commodityIndex\_";
									print $out "E_$vName\_$udEdges[$edge_out{$vName}[$i]][2]";
									print $out " false)";
									$h_edge{"$vName\_$udEdges[$edge_out{$vName}[$i]][2]"} = 1;
								}
							}
							for my $i (0 .. $#{$vedge_out{$vName}}){ # sink
								if(!exists($h_edge{"$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]"})){
									if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][3] || $virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][5][$commodityIndex]){
										$tmp_str ="N$nets[$netIndex][1]\_";
										$tmp_str.="C$commodityIndex\_";
										$tmp_str.="E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
										print $out " (= ";
										print $out $tmp_str;
										print $out " false)";
										$h_edge{"$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]"} = 1;
									}
								}
							}
						}
					}
					print $out ") (= true true)))\n";
					print $out "             (and (ite (bvult x$inst_pin_t (_ bv".($col-$LT>=0?($col-$LT):(0))." $lenV)) (and"; 
					%h_edge = ();
					for my $row (0 .. $numTrackH-1) {
						for my $metal (0 .. $numMetalLayer-1) { 
							my $vName = "m".$metal."r".$row."c".$col;
							for my $i (0 .. $#{$edge_in{$vName}}){ # incoming
								if(!exists($h_edge{"$udEdges[$edge_in{$vName}[$i]][1]_$vName"})){
									print $out " (= ";
									print $out "N$nets[$netIndex][1]\_";
									print $out "C$commodityIndex\_";
									print $out "E_$udEdges[$edge_in{$vName}[$i]][1]_$vName";
									print $out " false)";
									$h_edge{"$udEdges[$edge_in{$vName}[$i]][1]_$vName"} = 1;
								}
							}
							for my $i (0 .. $#{$edge_out{$vName}}){ # incoming
								if(!exists($h_edge{"$vName\_$udEdges[$edge_out{$vName}[$i]][2]"})){
									print $out " (= ";
									print $out "N$nets[$netIndex][1]\_";
									print $out "C$commodityIndex\_";
									print $out "E_$vName\_$udEdges[$edge_out{$vName}[$i]][2]";
									print $out " false)";
									$h_edge{"$vName\_$udEdges[$edge_out{$vName}[$i]][2]"} = 1;
								}
							}
							for my $i (0 .. $#{$vedge_out{$vName}}){ # sink
								if(!exists($h_edge{"$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]"})){
									if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][3] || $virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][5][$commodityIndex]){
										$tmp_str ="N$nets[$netIndex][1]\_";
										$tmp_str.="C$commodityIndex\_";
										$tmp_str.="E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
										print $out " (= ";
										print $out $tmp_str;
										print $out " false)";
										$h_edge{"$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]"} = 1;
									}
								}
							}
						}
					}
					print $out ") (= true true))\n";
					print $out "                  (ite (bvugt x$inst_pin_s (_ bv".($col+$LT>=$numTrackV-1?($numTrackV-1):($col+$LT>=0?($col+$LT):(0)))." $lenV)) (and"; 
					%h_edge = ();
					for my $row (0 .. $numTrackH-1) {
						for my $metal (0 .. $numMetalLayer-1) { 
							my $vName = "m".$metal."r".$row."c".$col;
							for my $i (0 .. $#{$edge_in{$vName}}){ # incoming
								if(!exists($h_edge{"$udEdges[$edge_in{$vName}[$i]][1]_$vName"})){
									print $out " (= ";
									print $out "N$nets[$netIndex][1]\_";
									print $out "C$commodityIndex\_";
									print $out "E_$udEdges[$edge_in{$vName}[$i]][1]_$vName";
									print $out " false)";
									$h_edge{"$udEdges[$edge_in{$vName}[$i]][1]_$vName"} = 1;
								}
							}
							for my $i (0 .. $#{$edge_out{$vName}}){ # incoming
								if(!exists($h_edge{"$vName\_$udEdges[$edge_out{$vName}[$i]][2]"})){
									print $out " (= ";
									print $out "N$nets[$netIndex][1]\_";
									print $out "C$commodityIndex\_";
									print $out "E_$vName\_$udEdges[$edge_out{$vName}[$i]][2]";
									print $out " false)";
									$h_edge{"$vName\_$udEdges[$edge_out{$vName}[$i]][2]"} = 1;
								}
							}
							for my $i (0 .. $#{$vedge_out{$vName}}){ # sink
								if(!exists($h_edge{"$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]"})){
									if($virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][3] || $virtualEdges[$vedge_out{$vName}[$i]][2] eq $nets[$netIndex][5][$commodityIndex]){
										$tmp_str ="N$nets[$netIndex][1]\_";
										$tmp_str.="C$commodityIndex\_";
										$tmp_str.="E_$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]";
										print $out " (= ";
										print $out $tmp_str;
										print $out " false)";
										$h_edge{"$vName\_$virtualEdges[$vedge_out{$vName}[$i]][2]"} = 1;
									}
								}
							}
						}
					}
					print $out ") (= true true)))))\n";
				}
			}
		}
	}
}
print $out ";End of Localization\n\n";


print "a   F. Check SAT & Optimization\n";
print $out ";F. Check SAT & Optimization\n";

my $isPRT_P = 0;
my $isPRT_N = 0;
if($CP == 1){
	my @arr_bound = ();
	for my $i (0 .. $lastIdxPMOS) {
		if(!exists($h_inst_group{$i})){
			push(@arr_bound, $i);
		}
	}
	my $numP = scalar @inst_group_p;
	if($numP > 0){
		my $numInstP = scalar @{$inst_group_p[0][1]};
		for my $j (0 .. $numInstP - 1){
			my $i = $inst_group_p[0][1][$j];
			push(@arr_bound, $i);
		}
	}

	my $numP = scalar @arr_bound;
	if($numP > 0){
		print $out "(assert (= COST_SIZE_P";
		for my $j (0 .. $numP - 2){
			print $out " (max";
		}
		my $i = $arr_bound[0];
		print $out " x$i";
		for my $j (1 .. $numP-1){
			my $i = $arr_bound[$j];
			print $out " x$i)";
		}
		print $out "))\n";
		$isPRT_P = 1;
	}

	@arr_bound = ();
	for my $i ($lastIdxPMOS + 1 .. $numInstance - 1) {
		if(!exists($h_inst_group{$i})){
			push(@arr_bound, $i);
		}
	}
	my $numN = scalar @inst_group_n;
	if($numN > 0){
		my $numInstN = scalar @{$inst_group_n[0][1]};
		for my $j (0 .. $numInstN - 1){
			my $i = $inst_group_n[0][1][$j];
			push(@arr_bound, $i);
		}
	}

	my $numN = scalar @arr_bound;
	if($numN > 0){
		print $out "(assert (= COST_SIZE_N";
		for my $j (0 .. $numN - 2){
			print $out " (max";
		}
		my $i = $arr_bound[0];
		print $out " x$i";
		for my $j (1 .. $numN-1){
			my $i = $arr_bound[$j];
			print $out " x$i)";
		}
		print $out "))\n";
		$isPRT_N = 1;
	}
}
else{
	print $out "(assert (= COST_SIZE_P";
	for my $j (0 .. scalar(@arr_pmos_fgroup)-2){
		print $out " (max";
	}
	my $i = $arr_pmos_fgroup[0];
	print $out " x$i";
	for my $j (1 .. scalar(@arr_pmos_fgroup)-1){
		my $i = $arr_pmos_fgroup[$j];
		print $out " x$i)";
	}
	print $out "))\n";

	print $out "(assert (= COST_SIZE_N";
	for my $j (0 .. scalar(@arr_nmos_fgroup) - 2) {
		print $out " (max";
	}
	my $i = $arr_nmos_fgroup[0];
	print $out " x$i";
	for my $j (1 .. scalar(@arr_nmos_fgroup)-1) {
		my $i = $arr_nmos_fgroup[$j];
		print $out " x$i)";
	}
	print $out "))\n";
}

my $dInt = 2;
my $dInt_r = 1;
print $out ";Pin Accessibility\n";
# Pin Accessibility
foreach my $key1(sort(keys %h_extnets)){
	for my $col(0 .. $numTrackV-1){
		print $out "(assert (= N$key1\_C$col\_EN (or";
		for my $row(1 .. $numTrackH-2){
			my $metal = $numMetalLayer - 2;
			my $vName = "m".$metal."r".$row."c".$col;
			print $out " N$key1\_E\_$vName\_pinSON";
		}
		print $out ")))\n";
	}
	for my $row(1 .. $numTrackH-2){
		print $out "(assert (= N$key1\_R$row\_EN (or";
		for my $col(0 .. $numTrackV-1){
			my $metal = $numMetalLayer - 2;
			my $vName = "m".$metal."r".$row."c".$col;
			print $out " N$key1\_E\_$vName\_pinSON";
		}
		print $out ")))\n";
	}
}
foreach my $key1(sort(keys %h_extnets)){
	for my $col(0 .. $numTrackV-1){
		print $out "(assert (= N$key1\_C$col (ite (= N$key1\_C$col\_EN true) (bvadd";
		my $low = ($col-$dInt>=0)?($col-$dInt):0;
		my $high = ($col+$dInt<=$numTrackV-1)?($col+$dInt):($numTrackV-1);
		for my $col2($low .. $high){
			foreach my $key2(sort(keys %h_extnets)){
				if($key1 == $key2) { next;}
				print $out " (ite (= N$key2\_C$col2\_EN true) (_ bv1 $lenN) (_ bv0 $lenN))";
			}
		}
		print $out ") (_ bv0 $lenN))))\n";
	}
	for my $row(1 .. $numTrackH-2){
		print $out "(assert (= N$key1\_R$row (ite (= N$key1\_R$row\_EN true) (bvadd";
		my $low = ($row-$dInt_r>=1)?($row-$dInt_r):1;
		my $high = ($row+$dInt<=$numTrackH-2)?($row+$dInt_r):($numTrackH-2);
		for my $row2($low .. $high){
			foreach my $key2(sort(keys %h_extnets)){
				if($key1 == $key2) { next;}
				print $out " (ite (= N$key2\_R$row2\_EN true) (_ bv1 $lenR) (_ bv0 $lenR))";
			}
		}
		print $out ") (_ bv0 $lenR))))\n";
	}
}

print $out "(assert (= COST_SIZE (max COST_SIZE_P COST_SIZE_N)))\n";

print $out "(minimize COST_SIZE)\n";

print $out "(maximize (bvadd";
for my $i(0 .. $numInstance-1){
	print $out " t$i";
}
print $out "))\n";

print $out "(minimize (bvadd";
foreach my $key1(sort(keys %h_extnets)){
	for my $col(0 .. $numTrackV-1){
		print $out " N$key1\_C$col";
	}
}
print $out "))\n";

print $out "(minimize (bvadd";
foreach my $key1(sort(keys %h_extnets)){
	for my $row(1 .. $numTrackH-2){
		print $out " N$key1\_R$row";
	}
}
print $out "))\n";

# Number of Last Metal Layer Track
print $out "(minimize (bvadd";
for my $row (0 .. $numTrackH-1) {
	print $out " (ite (= LM_TRACK_$row true) (_ bv1 $lenH) (_ bv0 $lenH))";
}
print $out "))\n";

my $metal = $numMetalLayer - 1;
my $idx_obj = 0;
my $str = "";

for my $udeIndex (0 .. $#udEdges) {
	if(!exists($h_preassign{"M_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2]"})){
		my $fromMetal = (split /[a-z]/, $udEdges[$udeIndex][1])[1]; # 1:metal 2:row 3:col
		my $toMetal = (split /[a-z]/, $udEdges[$udeIndex][2])[1];
		my $fromCol = (split /[a-z]/, $udEdges[$udeIndex][1])[3]; # 1:metal 2:row 3:col
		my $toCol = (split /[a-z]/, $udEdges[$udeIndex][2])[3];

		if($fromMetal==$toMetal && ($toMetal>=$metal && $toMetal<=$metal)){
			$str.=" (ite (= M_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] true) (_ bv1 32) (_ bv0 32))";
			$idx_obj++;
		}
	}
}
if($idx_obj > 0){
	print $out "(minimize (bvadd";
	print $out $str;
	print $out "))\n";
	$idx_obj = 0;
	$str = "";
}

for my $metal (0 .. $numMetalLayer-2){
	my $idx_obj = 0;
	my $str = "";

	for my $udeIndex (0 .. $#udEdges) {
		if(!exists($h_preassign{"M_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2]"})){
			my $fromMetal = (split /[a-z]/, $udEdges[$udeIndex][1])[1]; # 1:metal 2:row 3:col
			my $toMetal = (split /[a-z]/, $udEdges[$udeIndex][2])[1];
			my $fromCol = (split /[a-z]/, $udEdges[$udeIndex][1])[3]; # 1:metal 2:row 3:col
			my $toCol = (split /[a-z]/, $udEdges[$udeIndex][2])[3];

			if($fromMetal!=$toMetal && ($toMetal>=$metal+1 && $toMetal<=$metal+1)){
				$str.=" (ite (= M_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] true) (_ bv1 32) (_ bv0 32))";
				$idx_obj++;
			}
		}
	}
	if($idx_obj > 0){
		print $out "(minimize (bvadd";
		print $out $str;
		print $out "))\n";
		$idx_obj = 0;
		$str = "";
	}

	$idx_obj = 0;
	$str = "";

	for my $udeIndex (0 .. $#udEdges) {
		if(!exists($h_preassign{"M_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2]"})){
			my $fromMetal = (split /[a-z]/, $udEdges[$udeIndex][1])[1]; # 1:metal 2:row 3:col
			my $toMetal = (split /[a-z]/, $udEdges[$udeIndex][2])[1];
			my $fromCol = (split /[a-z]/, $udEdges[$udeIndex][1])[3]; # 1:metal 2:row 3:col
			my $toCol = (split /[a-z]/, $udEdges[$udeIndex][2])[3];

			if($fromMetal==$toMetal && ($toMetal>=$metal && $toMetal<=$metal)){
				$str.=" (ite (= M_$udEdges[$udeIndex][1]_$udEdges[$udeIndex][2] true) (_ bv1 32) (_ bv0 32))";
				$idx_obj++;
			}
		}
	}
	if($idx_obj > 0){
		print $out "(minimize (bvadd";
		print $out $str;
		print $out "))\n";
		$idx_obj = 0;
		$str = "";
	}
}

print $out "(check-sat)\n";
print $out "(get-model)\n";
print $out "(get-objectives)\n";
close ($out);
print "$outfile has been generated!!\n";
