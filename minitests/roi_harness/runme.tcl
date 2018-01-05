# WARNING: this is somewhat paramaterized, but is only tested on A50T/A35T with the traditional ROI
# Your ROI should at least have a SLICEL on the left

set DIN_N 8
set DOUT_N 8
# X12 in the ROI, X10 just to the left
# Start at bottom left of ROI and work up
# (IOs are to left)
# SLICE_X12Y100:SLICE_X27Y149
# set X_BASE 12
set X_BASE [lindex [split [lindex [split "$::env(XRAY_ROI)" Y] 0] X] 1]
set Y_BASE [lindex [split [lindex [split "$::env(XRAY_ROI)" Y] 1] :] 0]
# set Y_DIN_BASE 100
set Y_CLK_BASE $Y_BASE 
# Clock lut in middle
set Y_DIN_BASE [expr "$Y_CLK_BASE + 1"]
set Y_DOUT_BASE [expr "$Y_DIN_BASE + $DIN_N"]

puts "Environment"
puts "  XRAY_ROI: $::env(XRAY_ROI)"
puts "  X_BASE: $X_BASE"
puts "  Y_DIN_BASE: $Y_DIN_BASE"
puts "  Y_CLK_BASE: $Y_CLK_BASE"
puts "  Y_DOUT_BASE: $Y_DOUT_BASE"

source ../../utils/utils.tcl

create_project -force -part $::env(XRAY_PART) design design
read_verilog top.v
# added flatten_hierarchy
# dout_shr was getting folded into the pblock
# synth_design -top top -flatten_hierarchy none -no_lc -keep_equivalent_registers -resource_sharing off
synth_design -top top -flatten_hierarchy none -verilog_define DIN_N=$DIN_N -verilog_define DOUT_N=$DOUT_N

# TODO: find a way to more automatically assign these?
# Sequential I/O Bank 16 layout
set part "$::env(XRAY_PART)"
if {$part eq "xc7a50tfgg484-1"} {
    # Partial list, expand as needed
    set bank_16 "F21 G22 G21 D21 E21 D22 E22 A21 B21 B22 C22 C20 D20 F20 F19 A19 A18"
    set banki 0

    # CLK
    set pin [lindex $bank_16 $banki]
    incr banki
    set_property -dict "PACKAGE_PIN $pin IOSTANDARD LVCMOS33" [get_ports "clk"]

    # DIN
    for {set j 0} {$j < $DIN_N} {incr j} {
        set pin [lindex $bank_16 $banki]
        incr banki
        set_property -dict "PACKAGE_PIN $pin IOSTANDARD LVCMOS33" [get_ports "din[$j]"]
    }

    # DOUT
    for {set j 0} {$j < $DOUT_N} {incr j} {
        set pin [lindex $bank_16 $banki]
        incr banki
        set_property -dict "PACKAGE_PIN $pin IOSTANDARD LVCMOS33" [get_ports "dout[$j]"]
   }
# Arty A7 optimized I/O layout
} elseif {$part eq "xc7a35tcsg324-1"} {
    # https://reference.digilentinc.com/reference/programmable-logic/arty/reference-manual?redirect=1
    set pmod_ja "G13 B11 A11 D12  D13 B18 A18 K16"
    set pmod_jb "E15 E16 D15 C15  J17 J18 K15 J15"
    set pmod_jc "U12 V12 V10 V11  U14 V14 T13 U13"

    # CLK on Pmod JA
    set pin [lindex $pmod_ja 0]
    set_property -dict "PACKAGE_PIN G13 IOSTANDARD LVCMOS33" [get_ports "clk"]

    # DIN on Pmod JB
    for {set i 0} {$i < $DIN_N} {incr i} {
        set pin [lindex $pmod_jb $i]
        set_property -dict "PACKAGE_PIN $pin IOSTANDARD LVCMOS33" [get_ports "din[$i]"]
    }

    # DOUT on Pmod JC
    for {set i 0} {$i < $DOUT_N} {incr i} {
        set pin [lindex $pmod_jc $i]
        set_property -dict "PACKAGE_PIN $pin IOSTANDARD LVCMOS33" [get_ports "dout[$i]"]
   }
} else {
    error "Unsupported part $part"
}

create_pblock roi
set_property EXCLUDE_PLACEMENT 1 [get_pblocks roi]
add_cells_to_pblock [get_pblocks roi] [get_cells roi]
resize_pblock [get_pblocks roi] -add "$::env(XRAY_ROI)"

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.PERFRAMECRC YES [current_design]

set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clk_IBUF]

#write_checkpoint -force synth.dcp



proc loc_roi_clk_left {ff_x ff_y} {
    # Place an ROI clk on the left edge of the ROI
    # It doesn't actually matter where we place this, just do it to keep things neat looking
    # ff_x: ROI SLICE X position
    # ff_yy: row primitives will be placed at

    set slice_ff "SLICE_X${ff_x}Y${ff_y}"

    # Fix FFs to guide route in
    set cell [get_cells "roi/clk_reg_reg"]
    set_property LOC $slice_ff $cell
    set_property BEL AFF $cell
}

proc loc_roi_in_left {index lut_x y} {
    # Place an ROI input on the left edge of the ROI
    # index: input bus index
    # lut_x: ROI SLICE X position. FF position is implicit to left
    # y: row primitives will be placed at

    set slice_lut "SLICE_X${lut_x}Y${y}"

    # Fix LUTs near the edge
    set cell [get_cells "roi/ins[$index].lut"]
    set_property LOC $slice_lut $cell
    set_property BEL A6LUT $cell
}

proc loc_roi_out_left {index lut_x y} {
    # Place an ROI output on the left edge of the ROI
    # index: input bus index
    # lut_x: ROI SLICE X position. FF position is implicit to left
    # y: row primitives will be placed at

    set slice_lut "SLICE_X${lut_x}Y${y}"

    # Fix LUTs near the edge
    set cell [get_cells "roi/outs[$index].lut"]
    set_property LOC $slice_lut $cell
    set_property BEL A6LUT $cell
}


if {1} {
    set x $X_BASE

    # Place ROI clock right after inputs
    puts "Placing ROI clock"
    loc_roi_clk_left $x $Y_CLK_BASE

    # Place ROI inputs
    puts "Placing ROI inputs"
    set y $Y_DIN_BASE
    for {set i 0} {$i < $DIN_N} {incr i} {
        loc_roi_in_left $i $x $y
        set y [expr {$y + 1}]
    }

    # Place ROI outputs
    set y $Y_DOUT_BASE
    puts "Placing ROI outputs"
    for {set i 0} {$i < $DOUT_N} {incr i} {
        loc_roi_out_left $i $x $y
        set y [expr {$y + 1}]
    }
}

place_design
#write_checkpoint -force placed.dcp

# Version with more error checking for missing end node
# Will do best effort in this case
proc route_via2 {net nodes} {
    # net: net as string
    # nodes: string list of one or more intermediate routing nodes to visit

	set net [get_nets $net]
	# Start at the net source
	set fixed_route [get_nodes -of_objects [get_site_pins -filter {DIRECTION == OUT} -of_objects $net]]
	# End at the net destination
	# For sone reason this doesn't always show up
	set site_pins [get_site_pins -filter {DIRECTION == IN} -of_objects $net]
    if {$site_pins eq ""} {
        puts "WARNING: could not find end node"
        #error "Could not find end node"
    } else {
    	set end_node [get_nodes -of_objects]
    	lappend nodes [$end_node]
	}

	puts ""
	puts "Routing net $net:"

	foreach to_node $nodes {
        if {$to_node eq ""} {
            error "Empty node"
        }

	    # Node string to object
		set to_node [get_nodes -of_objects [get_wires $to_node]]
		# Start at last routed position
		set from_node [lindex $fixed_route end]
		# Let vivado do heavy liftin in between
		set route [find_routing_path -quiet -from $from_node -to $to_node]
		if {$route == ""} {
		    # Some errors print a huge route
			puts [concat [string range "  $from_node -> $to_node" 0 1000] ": no route found - assuming direct PIP"]
			lappend fixed_route $to_node
		} {
			puts [concat [string range "  $from_node -> $to_node: $route" 0 1000] "routed"]
			set fixed_route [concat $fixed_route [lrange $route 1 end]]
		}
		set_property -quiet FIXED_ROUTE $fixed_route $net
	}

	set_property -quiet FIXED_ROUTE $fixed_route $net
	puts ""
}

# XXX: maybe add IOB?
set fp [open "design.txt" w]
puts $fp "name node"
if {1} {
    set x $X_BASE

    # Nothing needed for clk
    # It will go to high level interconnect that goes everywhere

    puts "Routing ROI inputs"
    # Arbitrary offset as observed
    set y [expr {$Y_DIN_BASE - 1}]
    for {set i 0} {$i < $DIN_N} {incr i} {
        #route_via2 "din_IBUF[$i]" "INT_R_X9Y${y}/NE2BEG3"
        # needed to force routes away to avoid looping into ROI
        #set x_EE2BEG3 [expr {$x - 2}]
        set x_EE2BEG3 7
        set x_NE2BEG3 9
        set node "INT_R_X${x_NE2BEG3}Y${y}/NE2BEG3"
        route_via2 "din_IBUF[$i]" "INT_R_X${x_EE2BEG3}Y${y}/EE2BEG3 $node"
        puts $fp "din[$i] $node"

        set y [expr {$y + 1}]
    }

    puts "Routing ROI outputs"
    # Arbitrary offset as observed
    set y [expr {$Y_DOUT_BASE + 0}]
    for {set i 0} {$i < $DOUT_N} {incr i} {
        # XXX: find a better solution if we need harness long term
        # works on 50t but not 35t
        if {$part eq "xc7a50tfgg484-1"} {
            set node "INT_L_X10Y${y}/WW2BEG0"
            route_via2 "roi/dout[$i]" "$node"
        # works on 35t but not 50t
        } elseif {$part eq "xc7a35tcsg324-1"} {
            set node "INT_L_X10Y${y}/SW6BEG0"
            route_via2 "roi/dout[$i]" "$node"
        } else {
            error "Unsupported part $part"
        }
        puts $fp "dout[$i] $node"
        set y [expr {$y + 1}]
    }
}
close $fp

puts "routing design"
route_design

write_checkpoint -force design.dcp
write_bitstream -force design.bit
