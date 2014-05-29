Overview
========

LEDscape is a library for controlling 48 channels of WS2811-based LEDs from
a single Beagle Bone Black. It makes use of the two Programmable Realtime Units (PRUs),
each controlling 24 outputs. It can drive strings of 256 LEDs at around 60fps
and 512 LEDs at 30 30fps, enabling a single BBB to control 24,576 LEDs at once.

The libary can be used directly from C or C++ or data can be sent using the
Open Pixel Control protocol (http://openpixelcontrol.org) from a variety of
sources (e.g. Processing, Java, Python, etc...)

Background
------
LEDscape was originally written by Trammell Hudson (http://trmm.net/Category:LEDscape) for
controlling WS2811-based LEDs. Since his original work, his version (https://github.com/osresearch/LEDscape)
has been repurposed to drive a different type of LED panel (e.g. http://www.adafruit.com/products/420).

This version of the library was forked from his original WS2811 work. Various
improvements have been made in the attempt to make an accessible and powerful
ws2811 driver based on the BBB. Many thanks to Trammell for his execellent work
in scaffolding the BBB and PRUs for driving LEDs.


WARNING
=======

This code works with the PRU units on the Beagle Bone and can easily
cause *hard crashes*.  It is still being debugged and developed.
Be careful hot-plugging things into the headers -- it is possible to
damage the pin drivers and cause problems in the ARM, especially if
there are +5V signals involved.


Installation and Usage
========

To use LEDscape, download it to your BeagleBone Black.

First, make sure that LEDscape compiles:

	make

Before LEDscape will function, you will need to replace the device tree
file and reboot.

	# Some distros (e.g. Arch) keep these files in /boot/dtbs instead.
	cp /boot/am335x-boneblack.dtb{,.preledscape_bk}
	cp am335x-boneblack.dtb /boot/
	reboot


You will also need to have the uio_pruss module loaded.
	
	modprobe uio_pruss

You can now test LEDscape, run the following to display a map of how
the LEDscape strip ordering coreesponds to the GPIO pins on the BBB:

	node pinmap.js

Connect a WS2811-based LED chain to the Beagle Bone. The strip must
be running at the same voltage as the data signal. If you are using
an external 5v supply for the LEDs, you'll need to use a level shifter
or other technique to bring the BBB's 3.3v signals up to 5v.

Once everything is connected, run the `rgb-test` program:

	sudo ./rgb-test

The LEDs should now be fading prettily. If not, go back and make
sure everything is setup correctly.

Open Pixel Control Server
=========================

Setup
-----

Once you have LEDscape sending data to your pixels, you will probably
want to use the `opc-server` server which accepts Open Pixel Control data
and passes it on to LEDscape. There is an systemd service
checked in, which can be installed like so:

	sudo systemctl enable /path/to/LEDscape/ledscape.service
	sudo systemctl start ledscape

Note that you must specify an absolute path. Relative paths will not
work with systemctl to enable services.

If you would prefer to run the receiver without adding it as a service:

	sudo run-ledscape
	
By default LEDscape is configured for strings of 256 pixels, accepting OPC
data on port 7890. You can adjust this by editing the run script and 
editing the parameters to opc-rx.

Data Format
-----------

The `opc-server` server accepts data on OPC channel 0. It expects the data for
each LED strip concatonated together. This is done because LEDscape requires
that data for all strips be present at once before flushing data data out to
the LEDs. 

Features and Options
--------------------

`opc-server` supports Fadecandy-inspired temporal dithering and interpolation
to enhance the smoothness of the output data. By default, it will apply a
luminance curve, interpolate and dither input data at the highest framerate
possible with the given number of LEDs.

These options can be configured by command-line swithes that are lightly
documented by `opc-server -h`. The most common setup will be:

	./opc-server --count LED_COUNT --strip-count STRIP_COUNT
	
Note that future versions of `opc-server` will make use of a JSON configuration
and the current flags will be deprecated or removed.



Processing Example
========

The easiest way to see that LEDscape can receive arbitrary data is to run
the included Processing sketch, based on the examples from 
FadeCandy (https://github.com/scanlime/fadecandy). There is a 16x16 panel
example in processing/grid16x16_clouds. Edit the example to point at your
beaglebone's hostname or IP and run 


Hardware Tips
========

Connecting the LEDs to the correct pins and level-shifting the voltages
to 5v can be quite complex when using many output ports of the BBB. While
there may be others, RGB123 makes an execellent 24-pin cape designed 
specifically for this version of LEDscape: http://rgb-123.com/product/beaglebone-black-24-output-cape/

If you do not use a cape, refer to the pin mapping section below and remember
that the BBB outputs data at 3.3v. If you run your LEDs at 5v (which most are),
you will need to use a level-shifter of some sort. Adafruit has a decent one
which works well: http://www.adafruit.com/products/757

Disabling HDMI
========

If you need to use all 48 pins made available by LEDscape, you'll have
to disable the HDMI "cape" on the BeagleBone Black.

Mount the FAT32 partition, either through linux on the BeagleBone or
by plugging the USB into a computer, and add the following to the
first line of `uEnv.txt'

	capemgr.disable_partno=BB-BONELT-HDMI,BB-BONELT-HDMIN

It should read something like

	optargs=quiet drm.debug=7 capemgr.disable_partno=BB-BONELT-HDMI,BB-BONELT-HDMIN

Then reboot the BeagleBone Black.


Pin Mapping
========

The mapping from LEDscape channel to BeagleBone GPIO pin can be generated by running the pinmap script:

	node pinmap.js

As of this writing, it generates the following:

		                       LEDscape Channel Index
	 Row  Pin#       P9        Pin#  |  Pin#       P8        Pin# Row
	  1    1                    2    |   1                    2    1
	  2    3                    4    |   3                    4    2
	  3    5                    6    |   5                    6    3
	  4    7                    8    |   7     25      26     8    4
	  5    9                    10   |   9     28      27     10   5
	  6    11    13      23     12   |   11    16      15     12   6
	  7    13    14      21     14   |   13    10      11     14   7
	  8    15    19      22     16   |   15    18      17     16   8
	  9    17                   18   |   17    12      24     18   9
	  10   19                   20   |   19     9             20   10
	  11   21     1       0     22   |   21                   22   11
	  12   23    20             24   |   23                   24   12
	  13   25             7     26   |   25                   26   13
	  14   27            47     28   |   27    41             28   14
	  15   29    45      46     30   |   29    42      43     30   15
	  16   31    44             32   |   31     5       6     32   16
	  17   33                   34   |   33     4      40     34   17
	  18   35                   36   |   35     3      39     36   18
	  19   37                   38   |   37    37      38     38   19
	  20   39                   40   |   39    35      36     40   20
	  21   41     8       2     42   |   41    33      34     42   21
	  22   43                   44   |   43    31      32     44   22
	  23   45                   46   |   45    29      30     46   23
	  
	              ^       ^                    ^       ^
	              |-------|--------------------|-------|
	                     LEDscape Channel Indexes


Implementation Notes
========

The WS281x LED chips are built like shift registers and make for very
easy LED strip construction.  The signals are duty-cycle modulated,
with a 0 measuring 250 ns long and a 1 being 600 ns long, and 1250 ns
between bits.  Since this doesn't map to normal SPI hardware and requires
an 800 KHz bit clock, it is typically handled with a dedicated microcontroller
or DMA hardware on something like the Teensy 3.

However, the TI AM335x ARM Cortex-A8 in the BeagleBone Black has two
programmable "microcontrollers" built into the CPU that can handle realtime
tasks and also access the ARM's memory.  This allows things that
might have been delegated to external devices to be handled without
any additional hardware, and without the overhead of clocking data out
the USB port.

The frames are stored in memory as a series of 4-byte pixels in the
order GRBA, packed in strip-major order.  This means that it looks
like this in RAM:

	S0P0 S1P0 S2P0 ... S31P0 S0P1 S1P1 ... S31P1 S0P2 S1P2 ... S31P2

This way length of the strip can be variable, although the memory used
will depend on the length of the longest strip.  4 * 32 * longest strip
bytes are required per frame buffer.  The maximum frame rate also depends
on the length of th elongest strip.


API
===

`ledscape.h` defines the API. The key components are:

	ledscape_t * ledscape_init(unsigned num_pixels)
	ledscape_frame_t * ledscape_frame(ledscape_t*, unsigned frame_num);
	ledscape_draw(ledscape_t*, unsigned frame_num);
	unsigned ledscape_wait(ledscape_t*)

You can double buffer like this:

	const int num_pixels = 256;
	ledscape_t * const leds = ledscape_init(num_pixels);

	unsigned i = 0;
	while (1)
	{
		// Alternate frame buffers on each draw command
		const unsigned frame_num = i++ % 2;
		ledscape_frame_t * const frame
			= ledscape_frame(leds, frame_num);

		render(frame);

		// wait for the previous frame to finish;
		ledscape_wait(leds);
		ledscape_draw(leds, frame_num);
	}

	ledscape_close(leds);

The 24-bit RGB data to be displayed is laid out with BRGA format,
since that is how it will be translated during the clock out from the PRU.
The frame buffer is stored as a "strip-major" array of pixels.

	typedef struct {
		uint8_t b;
		uint8_t r;
		uint8_t g;
		uint8_t a;
	} __attribute__((__packed__)) ledscape_pixel_t;

	typedef struct {
		ledscape_pixel_t strip[32];
	} __attribute__((__packed__)) ledscape_frame_t;


Low level API
=============

If you want to poke at the PRU directly, there is a command structure
shared in PRU DRAM that holds a pointer to the current frame buffer,
the length in pixels, a command byte and a response byte.
Once the PRU has cleared the command byte you are free to re-write the
dma address or number of pixels.

	typedef struct
	{
		// in the DDR shared with the PRU
		const uintptr_t pixels_dma;

		// Length in pixels of the longest LED strip.
		unsigned num_pixels;

		// write 1 to start, 0xFF to abort. will be cleared when started
		volatile unsigned command;

		// will have a non-zero response written when done
		volatile unsigned response;
	} __attribute__((__packed__)) ws281x_command_t;

Reference
==========
* http://www.adafruit.com/products/1138
* http://www.adafruit.com/datasheets/WS2811.pdf
* http://processors.wiki.ti.com/index.php/PRU_Assembly_Instructions
