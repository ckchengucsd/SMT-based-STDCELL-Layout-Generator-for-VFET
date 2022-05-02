#! /usr/bin/perl

use strict 'vars';
use strict 'refs';
use strict 'subs';

use POSIX;

use Cwd;

### Revision History : Ver 1.0 #####
# 2022-04-30 SMT Result Converter for Initial Release
### Pre-processing ########################################################
my $ARGC        = @ARGV;
my $workdir     = getcwd();
my $outdir      = "$workdir/solutionsSMT";
my $pinLayoutdir      = "$workdir/pinLayouts";
my $infile      = "";
my $cellname	= "";

if ($ARGC != 2) {
    print "\n*** Error:: Wrong CMD";
    print "\n   [USAGE]: ./PL_FILE [inputfile_result] [org_cell_name]\n\n";
    exit(-1);
} else {
    $infile             = $ARGV[0];
    $cellname			= $ARGV[1];
}

if (!-e "./$infile") {
    print "\n*** Error:: FILE DOES NOT EXIST..\n";
    print "***         $workdir/$infile\n\n";
    exit(-1);
}
if (!-e "$pinLayoutdir/$cellname.pinLayout") {
    print "\n*** Error:: PinLayout FILE DOES NOT EXIST..\n";
    print "***         $pinLayoutdir/$cellname.pinLayout\n\n";
    exit(-1);
}

### Output Directory Creation, please see the following reference:
system "mkdir -p $outdir";

my $infileStatus = "init";

## Instance Info
my @inst = ();
my %h_inst = ();
my $idx_inst = 0;
my %h_inst_res = ();
## Metal/VIA Info
my @metal = ();
my @via = ();
my @final_metal = ();
my @final_via = ();
my @m_metal = ();
my %h_metal = ();
my %h_m_metal = ();
my $idx_m_metal = 0;
## Wire
my @wire = ();
my @via_wire = ();
my %h_wire = ();
my %h_via_wire = ();
## Internal Pin Info
my @pin = ();
my @extpin = ();
my @extpin_vdd = ();
my @extpin_vss = ();
my %h_pin = ();
my %h_extpin = ();
my %h_extpin_vdd = ();
my %h_extpin_vss = ();
## Net
my @net = ();
my %h_net = ();
my %h_net_cost = ();
my %h_net_metal = ();
my %h_net_vertex = ();
my $net_idx = 0;
## Cost
my $cost_placement = 0;
my $cost_ml = 0;
my $cost_ml2 = 0;
my $cost_wl = 0;
my $no_m2_track = 0;
my $cost_via = 0;
my $cost_m = 0;
my $cost_lm = 0;

my $c_v0 = 0;
my $c_v1 = 0;
my $c_v2 = 0;
my $c_m0 = 0;
my $c_m1 = 0;
my $c_m2 = 0;

my $isFirst = 1;
my $subIndex = 0;

my $out;
my $outfile = "";
### metal vertices
my %h_vertices = ();
### Read External Pin Name
my %h_extpinname = ();
my %h_extpintype = ();
my $numTrackV = 0;
my $numTrackH = 0;
my $numTrackHPerClip = 0;
my $numRoutingClip = 0;
my $typePowerRail = 0;
my $trackPFET = 0;
my $trackNFET = 0;
my $typeStack = 0;
my $numTier = 0;
my $numMetalLayer = 0;
my $numInstance = 0;
my %h_inst_idx = ();
my %h_track = ();
my %h_numTrack = ();
open (my $in, "$pinLayoutdir/$cellname.pinLayout");
while (<$in>) {
    my $line = $_;
    chomp($line);

    ### Status of Input File
    if ($line =~ /===InstanceInfo===/) {
        $infileStatus = "inst";
    } 
    elsif ($line =~ /===NetInfo===/) {
        $infileStatus = "net";
    }
    elsif ($line =~ /===PinInfo===/) {
        $infileStatus = "pin";
    }
    if ($infileStatus eq "inst") {
		if ($line =~ /^i   ins(\S+)\s*(\S+)\s*(\d+)/) {	
			$h_inst_idx{$numInstance} = $1;
			$numInstance++;
		}
	}
    if ($line =~ /^i.*pin.*net(\d+) ext (\S+) t -1 (\S+)/) {
		my $netID = $1;
		my $pinName = $2;
		$h_extpinname{$1}=$2;
		$h_extpintype{$1}=$3;
	}
    if ($line =~ /^a.*Width of Routing Clip.*= (\S+)/) {
		$numTrackV = $1;
	}
}
close($in);

### Read Inputfile and Build Data Structure
open (my $in, "./$infile");
while (<$in>) {
    my $line = $_;
    chomp($line);

    ### Instance
    if ($line =~ /^.*\(define-fun x(\d+)/) {
		my $tmp = $1;
		$line = <$in>;
		chomp($line);
		if($line =~ /^\s+#x(\S+)\)/){
			$line =~ s/^\s+#x(\S+)\)/$1/g;
			$line = eval("0x$line");
		}
		else{
			$line =~ s/^\s+#b(\S+)\)/$1/g;
			$line = eval("0b$line");
		}
		if(exists($h_inst{$tmp})){
			$inst[$h_inst{$tmp}][1] = $line;
		}
		else{
			push(@inst, [($tmp, $line, -1, -1, -1)]);
			$h_inst{$tmp} = $idx_inst;
			$idx_inst++;
		}
    } 
    elsif ($line =~ /^.*\(define-fun y(\d+)/) {
		my $tmp = $1;
		$line = <$in>;
		chomp($line);
		if($line =~ /^\s+#x(\S+)\)/){
			$line =~ s/^\s+#x(\S+)\)/$1/g;
			$line = eval("0x$line");
		}
		else{
			$line =~ s/^\s+#b(\S+)\)/$1/g;
			$line = eval("0b$line");
		}
		if(exists($h_inst{$tmp})){
			$inst[$h_inst{$tmp}][2] = $line;
		}
		else{
			push(@inst, [($tmp, -1, $line, -1, -1)]);
			$h_inst{$tmp} = $idx_inst;
			$idx_inst++;
		}
    } 
    elsif ($line =~ /^.*\(define-fun t(\d+)/) {
		my $tmp = $1;
		$line = <$in>;
		chomp($line);
		if($line =~ /^\s+#x(\S+)\)/){
			$line =~ s/^\s+#x(\S+)\)/$1/g;
			$line = eval("0x$line");
		}
		else{
			$line =~ s/^\s+#b(\S+)\)/$1/g;
			$line = eval("0b$line");
		}
		if(exists($h_inst{$tmp})){
			$inst[$h_inst{$tmp}][3] = $line;
		}
		else{
			push(@inst, [($tmp, -1, -1, $line, -1)]);
			$h_inst{$tmp} = $idx_inst;
			$idx_inst++;
		}
    } 
    elsif ($line =~ /^.*\(define-fun w(\d+)/) {
		my $tmp = $1;
		$line = <$in>;
		chomp($line);
		if($line =~ /^\s+#x(\S+)\)/){
			$line =~ s/^\s+#x(\S+)\)/$1/g;
			$line = eval("0x$line");
		}
		else{
			$line =~ s/^\s+#b(\S+)\)/$1/g;
			$line = eval("0b$line");
		}
		if(exists($h_inst{$tmp})){
			$inst[$h_inst{$tmp}][4] = $line;
		}
		else{
			push(@inst, [($tmp, -1, -1, -1, $line)]);
			$h_inst{$tmp} = $idx_inst;
			$idx_inst++;
		}
    } 
    elsif ($line =~ /^.*\(define-fun numTier/) {
		my $tmp = $1;
		$line = <$in>;
		chomp($line);
		if($line =~ /^\s+#x(\S+)\)/){
			$line =~ s/^\s+#x(\S+)\)/$1/g;
			$line = eval("0x$line");
		}
		else{
			$line =~ s/^\s+#b(\S+)\)/$1/g;
			$line = eval("0b$line");
		}
		$numTier = $line;
		$numMetalLayer = $numTier * 2 + 1 + 1;
    } 
    elsif ($line =~ /^.*\(define-fun typeStack/) {
		my $tmp = $1;
		$line = <$in>;
		chomp($line);
		if($line =~ /^\s+#x(\S+)\)/){
			$line =~ s/^\s+#x(\S+)\)/$1/g;
			$line = eval("0x$line");
		}
		else{
			$line =~ s/^\s+#b(\S+)\)/$1/g;
			$line = eval("0b$line");
		}
		$typeStack = $line;
    } 
    elsif ($line =~ /^.*\(define-fun typePowerRail/) {
		my $tmp = $1;
		$line = <$in>;
		chomp($line);
		if($line =~ /^\s+#x(\S+)\)/){
			$line =~ s/^\s+#x(\S+)\)/$1/g;
			$line = eval("0x$line");
		}
		else{
			$line =~ s/^\s+#b(\S+)\)/$1/g;
			$line = eval("0b$line");
		}
		$typePowerRail = $line;
    } 
    elsif ($line =~ /^.*\(define-fun trackH/) {
		my $tmp = $1;
		$line = <$in>;
		chomp($line);
		if($line =~ /^\s+#x(\S+)\)/){
			$line =~ s/^\s+#x(\S+)\)/$1/g;
			$line = eval("0x$line");
		}
		else{
			$line =~ s/^\s+#b(\S+)\)/$1/g;
			$line = eval("0b$line");
		}
		$numTrackH = $line;
    } 
    elsif ($line =~ /^.*\(define-fun trackPFET/) {
		my $tmp = $1;
		$line = <$in>;
		chomp($line);
		if($line =~ /^\s+#x(\S+)\)/){
			$line =~ s/^\s+#x(\S+)\)/$1/g;
			$line = eval("0x$line");
		}
		else{
			$line =~ s/^\s+#b(\S+)\)/$1/g;
			$line = eval("0b$line");
		}
		$trackPFET= $line;
    } 
    elsif ($line =~ /^.*\(define-fun trackNFET/) {
		my $tmp = $1;
		$line = <$in>;
		chomp($line);
		if($line =~ /^\s+#x(\S+)\)/){
			$line =~ s/^\s+#x(\S+)\)/$1/g;
			$line = eval("0x$line");
		}
		else{
			$line =~ s/^\s+#b(\S+)\)/$1/g;
			$line = eval("0b$line");
		}
		$trackNFET= $line;
    } 
}
close ($in);

open (my $in, "./$infile");
while (<$in>) {
    my $line = $_;
    chomp($line);

    ### Metal
    if ($line =~ /^.*\(define-fun M_m(\d+)r(\d+)c(\d+)_m(\d+)r(\d+)c(\d+)/) {
		my $fromM = $1;
		my $toM = $4;
		my $fromR = $2;
		my $toR = $5;
		my $fromC = $3;
		my $toC = $6;

		$line = <$in>;
		chomp($line);
		$line =~ s/^\s+(\S+)\)/$1/g;
		$line = $line eq "true"?1:0;

		if($line == 1){
			if(($fromR == 0 && $toR == 0) || ($fromR == $numTrackH - 1 && $toR == $numTrackH - 1)){
				next;
			}
			# Metal Line
			if($fromM == $toM){
				push(@metal, [($fromM, $fromR, $fromC, $toR, $toC)]);
				$h_vertices{"m".$fromM."r".$fromR."c".$fromC} = 1;
				$h_vertices{"m".$toM."r".$toR."c".$toC} = 1;
				$cost_ml2++;
				$cost_m++;
				if($fromM == 2 && $toM ==2){
					$c_m0++;
				}
				if($fromM == 3 && $toM ==3){
					$c_m1++;
				}
				if($fromM == 4 && $toM ==4){
					$c_m2++;
				}
			}
			else{
				push(@via, [($fromM, $toM, $fromR, $fromC)]);
				$cost_ml2 = $cost_ml2 + 4;
				$cost_via=$cost_via+4;
				if($fromM == 1 && $toM ==2){
					$c_v0++;
				}
				if($fromM == 2 && $toM ==3){
					$c_v1++;
				}
				if($fromM == 3 && $toM ==4){
					$c_v2++;
				}
			}
		}
    } 
    ### Wire
    if ($line =~ /^.*\(define-fun N(\S+)_C(\S+)_E_m(\d+)r(\d+)c(\d+)_m(\d+)r(\d+)c(\d+)/) {
		my $fromM = $3;
		my $toM = $6;
		my $fromR = $4;
		my $toR = $7;
		my $fromC = $5;
		my $toC = $8;

		$line = <$in>;
		chomp($line);
		$line =~ s/^\s+(\S+)\)/$1/g;
		$line = $line eq "true"?1:0;

		if($line == 1){
			if(!exists($h_wire{$fromM."_".$toM."_".$fromR."_".$fromC."_".$toR."_".$toC})){
				# Metal Line
				if($fromM == $toM){
					push(@wire, [($fromM, $fromR, $fromC, $toR, $toC)]);
					$cost_wl++;
				}
				else{
					push(@via_wire, [($fromM, $toM, $fromR, $fromC)]);
					$cost_wl = $cost_wl + 4;
				}
				$h_wire{$fromM."_".$toM."_".$fromR."_".$fromC."_".$toR."_".$toC} = 1;
			}
		}
    } 
    ### Net
    if ($line =~ /^.*\(define-fun N(\S+)_E_m(\d+)r(\d+)c(\d+)_m(\d+)r(\d+)c(\d+)/) {
		my $netID = $1;
		my $fromM = $2;
		my $toM = $5;
		my $fromR = $3;
		my $toR = $6;
		my $fromC = $4;
		my $toC = $7;

		$line = <$in>;
		chomp($line);
		$line =~ s/^\s+(\S+)\)/$1/g;
		$line = $line eq "true"?1:0;

		if($line == 1){
			if(!exists($h_net{$fromM."_".$toM."_".$fromR."_".$fromC."_".$toR."_".$toC})){
				push(@net, [($fromM, $fromR, $fromC, $toR, $toC)]);
				$h_net{$fromM."_".$toM."_".$fromR."_".$fromC."_".$toR."_".$toC} = $netID;
				$h_net{$fromM."_".$toM."_".$toR."_".$fromC."_".$fromR."_".$toC} = $netID;
				$h_net{$fromM."_".$toM."_".$fromR."_".$toC."_".$toR."_".$fromC} = $netID;
				$h_net{$toM."_".$fromM."_".$fromR."_".$fromC."_".$toR."_".$toC} = $netID;
				if(!exists($h_net_cost{$netID})){
					if($fromM == $toM){
						$h_net_cost{$netID} = 1;
					}
					else{
						$h_net_cost{$netID} = 4;
					}
				}
				else{
					if($fromM == $toM){
						$h_net_cost{$netID} = $h_net_cost{$netID} + 1;
					}
					else{
						$h_net_cost{$netID} = $h_net_cost{$netID} + 4;
					}
				}
				if(!exists($h_net_metal{$netID."_".$fromM})){
					$h_net_metal{$netID."_".$fromM} = 0;
				}
				if(!exists($h_net_metal{$netID."_".$toM})){
					$h_net_metal{$netID."_".$toM} = 0;
				}
				if(!exists($h_net_vertex{$netID."_m".$fromM."r".$fromR."c".$fromC})){
					$h_net_vertex{$netID."_m".$fromM."r".$fromR."c".$fromC} = 1;
					$h_net_metal{$netID."_".$fromM} = $h_net_metal{$netID."_".$fromM} + 1;
				}
				if(!exists($h_net_vertex{$netID."_m".$toM."r".$toR."c".$toC})){
					$h_net_vertex{$netID."_m".$toM."r".$toR."c".$toC} = 1;
					$h_net_metal{$netID."_".$toM} = $h_net_metal{$netID."_".$toM} + 1;
				}
			}
		}
    } 
    ### Pin
    if ($line =~ /^.*\(define-fun M_m(\d+)r(\d+)c(\d+)_(pin[a-zA-Z0-9_]+)/) {
		my $pinName = $4;
		my $metal = $1;
		my $row = $2;
		my $col = $3;

		$line = <$in>;
		chomp($line);
		$line =~ s/^\s+(\S+)\)/$1/g;
		$line = $line eq "true"?1:0;

		if($pinName =~ /.*SON.*/){
		}
		else{
			if($line == 1){
				if(!exists($h_pin{$pinName})){
					push(@pin, [($pinName, $row, $col, $metal)]);
					$h_pin{$pinName} = 1;
				}
			}
		}
	}
    ### ExtPin
	if ($line =~ /^.*\(define-fun N(\d+)_E_m(\d+)r(\d+)c(\d+)_pinSON_vdd/) {
		my $net = $1;
		my $metal = $2;
		my $row = $3;
		my $col = $4;

		$line = <$in>;
		chomp($line);
		$line =~ s/^\s+(\S+)\)/$1/g;
		$line = $line eq "true"?1:0;
		if($line == 1){
			if(!exists($h_extpin_vdd{$net})){
				push(@extpin_vdd, [($net, $metal, $row, $col)]);
				$h_extpin_vdd{$net} = 1;
			}
		}
	}
	if ($line =~ /^.*\(define-fun N(\d+)_E_m(\d+)r(\d+)c(\d+)_pinSON_vss/) {
		my $net = $1;
		my $metal = $2;
		my $row = $3;
		my $col = $4;

		$line = <$in>;
		chomp($line);
		$line =~ s/^\s+(\S+)\)/$1/g;
		$line = $line eq "true"?1:0;
		if($line == 1){
			if(!exists($h_extpin_vss{$net})){
				push(@extpin_vss, [($net, $metal, $row, $col)]);
				$h_extpin_vss{$net} = 1;
			}
		}
	}
	if ($line =~ /^.*\(define-fun N(\d+)_E_m(\d+)r(\d+)c(\d+)_pinSON/) {
		my $net = $1;
		my $metal = $2;
		my $row = $3;
		my $col = $4;

		$line = <$in>;
		chomp($line);
		$line =~ s/^\s+(\S+)\)/$1/g;
		$line = $line eq "true"?1:0;
		if($line == 1){
			if(!exists($h_extpin{$net})){
				push(@extpin, [($net, $metal, $row, $col)]);
				$h_extpin{$net} = $net_idx;
				$net_idx++;
			}
		}
	}
    ### Cost
    if ($line =~ /^.*\(define-fun COST_SIZE /) {
		$line = <$in>;
		chomp($line);
		if($line =~ /^\s+#x(\S+)\)/){
			$line =~ s/^\s+#x(\S+)\)/$1/g;
			$line = eval("0x$line");
		}
		else{
			$line =~ s/^\s+#b(\S+)\)/$1/g;
			$line = eval("0b$line");
		}
		$cost_placement = $line+1;
	}
    if ($line =~ /^.*\(define-fun cost_ML/) {
		$line = <$in>;
		chomp($line);
		$line =~ s/^\s+(\d+)\)/$1/g;
		$cost_ml = $line;
	}
    if ($line =~ /^.*\(define-fun M(\d+)_TRACK(\S+)_(\d+)/) {
		my $m = $1;
		my $type = $2;
		my $track = $3;

		$line = <$in>;
		chomp($line);
		$line =~ s/^\s+(\S+)\)/$1/g;
		$line = $line eq "true"?1:0;
		if($line == 1){
			if(exists($h_track{"M$m $type"})){
				$h_track{"M$m $type"} = $h_track{"M$m $type"} + 1;
			}
			else {
				$h_track{"M$m $type"} = 1;
			}
		}
	}
    if ($line =~ /^.*\(define-fun LM_TRACK_(\d+)/) {
		my $track = $1;

		$line = <$in>;
		chomp($line);
		$line =~ s/^\s+(\S+)\)/$1/g;
		$line = $line eq "true"?1:0;
		if($line == 1){
			if(exists($h_track{"LM"})){
				$h_track{"LM"} = $h_track{"LM"} + 1;
			}
			else {
				$h_track{"LM"} = 1;
			}
		}
	}
}
close ($in);

#Check Stacked VIA
for my $i(0 .. (scalar @via) - 1){
	my $netID = $h_net{$via[$i][0]."_".$via[$i][1]."_".$via[$i][2]."_".$via[$i][3]."_".$via[$i][2]."_".$via[$i][3]};
	if(!exists($h_vertices{"m".$via[$i][0]."r".$via[$i][2]."c".$via[$i][3]})){
		push(@metal, [($via[$i][0], $via[$i][2], $via[$i][3], $via[$i][2], $via[$i][3])]);
		$h_net{$via[$i][0]."_".$via[$i][0]."_".$via[$i][2]."_".$via[$i][3]."_".$via[$i][2]."_".$via[$i][3]} = $netID;
	}
	if(!exists($h_vertices{"m".$via[$i][1]."r".$via[$i][2]."c".$via[$i][3]})){
		push(@metal, [($via[$i][1], $via[$i][2], $via[$i][3], $via[$i][2], $via[$i][3])]);
		$h_net{$via[$i][1]."_".$via[$i][1]."_".$via[$i][2]."_".$via[$i][3]."_".$via[$i][2]."_".$via[$i][3]} = $netID;
	}
}

#Check Dummy Gate
foreach my $key(keys %h_inst){
	$h_inst_res{$inst[$key][1]."_".$inst[$key][2]."_".$inst[$key][3]} = 1;
}
for my $tier(0 .. $numTier-1){
	for my $vt(0 .. $cost_placement-1){
		if(!exists($h_inst_res{$vt."_".$trackPFET."_".$tier})){
			print "Dummy Gate : X=$vt Y=$trackPFET Tier=$tier\n";
			push(@metal, [(($tier*2+1), $trackPFET, $vt, $trackPFET, $vt)]);
			$h_net{($tier*2+1)."_".($tier*2+1)."_".$trackPFET."_".$vt."_".$trackPFET."_".$vt} = -1;
		}
		if(!exists($h_inst_res{$vt."_".$trackNFET."_".$tier})){
			print "Dummy Gate : X=$vt Y=$trackNFET Tier=$tier\n";
			push(@metal, [(($tier*2+1), $trackNFET, $vt, $trackNFET, $vt)]);
			$h_net{($tier*2+1)."_".($tier*2+1)."_".$trackNFET."_".$vt."_".$trackNFET."_".$vt} = -1;
		}
	}
}

#Check Serially connected FETs
for my $tier(0 .. $numTier-2){
	my $target_m = ($tier+1)*2;
	my $l_tier = $tier;
	my $u_tier = $tier + 1;
	for my $vt(0 .. $cost_placement-1){
		if(exists($h_inst_res{$vt."_".$trackPFET."_".$l_tier}) && exists($h_inst_res{$vt."_".$trackPFET."_".$u_tier})){
			if(!exists($h_vertices{"m".$target_m."r".$trackPFET."c".$vt})){
				push(@metal, [($target_m, $trackPFET, $vt, $trackPFET, $vt)]);
				$h_net{$target_m."_".$target_m."_".$trackPFET."_".$vt."_".$trackPFET."_".$vt} = -1;
			}
		}
		if(exists($h_inst_res{$vt."_".$trackNFET."_".$l_tier}) && exists($h_inst_res{$vt."_".$trackNFET."_".$u_tier})){
			if(!exists($h_vertices{"m".$target_m."r".$trackNFET."c".$vt})){
				print "Serial FETs without middle metal segments : X=$vt Y=$trackNFET L_Tier=$l_tier U_Tier=$u_tier\n";
				push(@metal, [($target_m, $trackNFET, $vt, $trackNFET, $vt)]);
				$h_net{$target_m."_".$target_m."_".$trackNFET."_".$vt."_".$trackNFET."_".$vt} = -1;
			}
		}
	}
}

$outfile     = "$outdir/".(split /\./, (split /\//, $infile)[$#_])[0].".conv";
open ($out,'>', $outfile);
mergeVertices();
printResult();
close($out);

sub mergeVertices{
	my $idx_metal = 0;
	for my $i(0 .. (scalar @metal) -1){
		push(@final_metal, [($metal[$i][0], $metal[$i][1], $metal[$i][2], $metal[$i][3], $metal[$i][4])]);
		$h_metal{$metal[$i][0]."_".$metal[$i][0]."_".$metal[$i][1]."_".$metal[$i][2]."_".$metal[$i][3]."_".$metal[$i][4]} = $idx_metal;
		$idx_metal++;
	}
	for my $i(0 .. (scalar @via) -1){
		push(@final_via, [($via[$i][0], $via[$i][1], $via[$i][2], $via[$i][3])]);
	}
	my $prev_cnt = 0;
	my $cur_cnt = 0;
	$prev_cnt = keys %h_metal;
	$cur_cnt = keys %h_metal;
	while($cur_cnt > 0){
		if($prev_cnt == $cur_cnt){
			foreach my $key(keys %h_metal){
				my $idx = $h_metal{$key};
				my $netID = $h_net{$final_metal[$idx][0]."_".$final_metal[$idx][0]."_".$final_metal[$idx][1]."_".$final_metal[$idx][2]."_".$final_metal[$idx][3]."_".$final_metal[$idx][4]};
				push(@m_metal, [($final_metal[$idx][0], $final_metal[$idx][1], $final_metal[$idx][2], $final_metal[$idx][3], $final_metal[$idx][4], $netID)]);
				$h_m_metal{ $final_metal[$idx][0]."_".$final_metal[$idx][1]."_".$final_metal[$idx][2]."_".$final_metal[$idx][3]."_".$final_metal[$idx][4]} = $idx_m_metal;
				$idx_m_metal++;
				delete $h_metal{$key};
				last;
			}
		}
		$prev_cnt = keys %h_metal;
		foreach my $key(keys %h_metal){
			my $idx = $h_metal{$key};
			for(my $i=0; $i<=$#m_metal; $i++){
				if($m_metal[$i][0] eq $final_metal[$idx][0]){
					# Vertical
					if($final_metal[$idx][1] != $final_metal[$idx][3] && $m_metal[$i][1] != $m_metal[$i][3] && $m_metal[$i][2] == $m_metal[$i][4]){
						if($m_metal[$i][1] == $final_metal[$idx][3] && $m_metal[$i][2] == $final_metal[$idx][2]){
							$m_metal[$i][1] = $final_metal[$idx][1];
							delete $h_metal{$key};
						}
						elsif($m_metal[$i][3] == $final_metal[$idx][1] && $m_metal[$i][2] == $final_metal[$idx][2] && $m_metal[$i][2] == $m_metal[$i][4]){
							$m_metal[$i][3] = $final_metal[$idx][3];
							delete $h_metal{$key};
						}
					}
					# Horizontal
					elsif($final_metal[$idx][2] != $final_metal[$idx][4] && $m_metal[$i][2] != $m_metal[$i][4] && $m_metal[$i][1] == $m_metal[$i][3]){
						if($m_metal[$i][2] == $final_metal[$idx][4] && $m_metal[$i][1] == $final_metal[$idx][1]){
							$m_metal[$i][2] = $final_metal[$idx][2];
							delete $h_metal{$key};
						}
						elsif($m_metal[$i][4] == $final_metal[$idx][2] && $m_metal[$i][1] == $final_metal[$idx][1] && $m_metal[$i][1] == $m_metal[$i][3]){
							$m_metal[$i][4] = $final_metal[$idx][4];
							delete $h_metal{$key};
						}
					}
				}
			}
		}
		$cur_cnt = keys %h_metal;
	}
}

sub printResult{
	print $out "TRACK $numTrackV $numTrackH $typePowerRail $trackPFET $trackNFET $numTier $typeStack\r\n";
	print $out "COST $cost_placement $cost_ml $cost_wl\r\n";
	for my $i(0 .. (scalar @inst) -1){
		print $out "INST $h_inst_idx{$inst[$i][0]} $inst[$i][1] $inst[$i][2] $inst[$i][3] $inst[$i][4] $inst[$i][0]\r\n";
	}
	for my $i(0 .. (scalar @pin) -1){
		print $out "PIN $pin[$i][0] $pin[$i][1] $pin[$i][2] $pin[$i][3]\r\n";
	}
	for my $m (0 .. $numTier*2+1){
		for my $i(0 .. (scalar @m_metal) -1){
			if($m_metal[$i][0] == $m){
				my $netID = $h_net{$m_metal[$i][0]."_".$m_metal[$i][0]."_".$m_metal[$i][1]."_".$m_metal[$i][2]."_".$m_metal[$i][3]."_".$m_metal[$i][4]};
				print $out "METAL $m_metal[$i][0] $m_metal[$i][1] $m_metal[$i][2] $m_metal[$i][3] $m_metal[$i][4] $m_metal[$i][5]\r\n";
			}
		}
	}
	for my $m (0 .. $numTier*2-1+1){
		for my $i(0 .. (scalar @final_via) -1){
			if($final_via[$i][0] == (2*$numTier-$m) && $final_via[$i][1] == (2*$numTier+1-$m)){
				my $netID = $h_net{$final_via[$i][0]."_".$final_via[$i][1]."_".$final_via[$i][2]."_".$final_via[$i][3]."_".$final_via[$i][2]."_".$final_via[$i][3]};
				print $out "VIA $final_via[$i][0] $final_via[$i][1] $final_via[$i][2] $final_via[$i][3] $netID\r\n";
			}
		}
	}
	for my $i(0 .. (scalar @extpin) -1){
		print $out "EXTPIN $extpin[$i][0] $extpin[$i][1] $extpin[$i][2] $extpin[$i][3] $h_extpinname{$extpin[$i][0]} $h_extpintype{$extpin[$i][0]}\r\n";
	}
	for my $i(0 .. (scalar @extpin_vdd) -1){
		print $out "EXTPIN_VDD $extpin_vdd[$i][0] $extpin_vdd[$i][1] $extpin_vdd[$i][2] $extpin_vdd[$i][3] $h_extpinname{$extpin_vdd[$i][0]} $h_extpintype{$extpin_vdd[$i][0]}\r\n";
	}
	for my $i(0 .. (scalar @extpin_vss) -1){
		print $out "EXTPIN_VSS $extpin_vss[$i][0] $extpin_vss[$i][1] $extpin_vss[$i][2] $extpin_vss[$i][3] $h_extpinname{$extpin_vss[$i][0]} $h_extpintype{$extpin_vss[$i][0]}\r\n";
	}
	for my $key(sort(keys %h_net_cost)){
		if(exists($h_extpin{$key})){
			print "NETCOST NET$key [$h_extpinname{$extpin[$h_extpin{$key}][0]}] COST : $h_net_cost{$key} METAL :";
			for my $key2(sort(keys %h_net_metal)){
				my @tmp = split /_/, $key2;
				if($tmp[0] == $key){
					print " M".$tmp[1]."(".($h_net_metal{$key2}).")";
				}
			}
			print "\n";
		}
		else{
			print "NETCOST NET$key COST : $h_net_cost{$key}\n";
		}
	}
	for my $key(sort(keys %h_track)){
		print "#track $key : $h_track{$key}\n";
	}
	print "Converting Result Completed!\nOutput : $outfile\n";
}
