#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <inttypes.h>
#include <errno.h>
#include <unistd.h>
#include <sys/time.h>

extern "C" {
#include "ledscape.h"
}

#include "bonelib/nunchuck.hpp"

using namespace BeagleBone;

int main (void)
{
	const unsigned num_pixels = 52;
	ledscape_t * const leds = ledscape_init(num_pixels);

        ledscape_frame_t *frame[2];
	frame[0] = ledscape_frame(leds, 0);
	frame[1] = ledscape_frame(leds, 1);

	uint8_t rgb[3];
	rgb[0] = 255;
	rgb[1] = 255;
	rgb[2] = 255;

	unsigned use_frame = 0;
	unsigned ball = num_pixels/2;
	unsigned speed = 1;

	while (1)
	{
		// Read the Nunchuck
		nunchuck::sample();

		// Stop if both buttons are pressed
		if (nunchuck::Z() && nunchuck::C()) break;

                // Move the ball
		signed short daX = nunchuck::daX();
		// Horizontal position is at 25
		daX -= 25;

		if      (daX < -25) ball++;
		else if (daX >  25) ball--;
		ball = ball % num_pixels;

		daX = abs(daX);
		if      (daX >  126) speed = 3;
		else if (daX >   75) speed = 2;
                else                 speed = 1;

		// Set the color of the ballA
		float dX = ((float) nunchuck::dX()) / 100.0;
		float dY = ((float) nunchuck::dY()) / 100.0;
		if (dY < 0) {
			rgb[0] = 255 + (255*dY);
			rgb[1] = 255;
			rgb[2] = 255;
		} else {
			rgb[0] = 255;
			if (dX < 0) {
				rgb[1] = 255 - (255 * sqrtf(dX*dX+dY*dY)/sqrtf(2.0));
				rgb[2] = 255;
			} else {
				rgb[1] = 255;
				rgb[2] = 255 - (255 * sqrtf(dX*dX+dY*dY)/sqrtf(2.0));
			}

		}

		// Draw the ball
		for (unsigned p = 0 ; p < num_pixels; p++) {
			ledscape_set_color(frame[use_frame], 0, p,
				(p == ball) ? rgb[0] : 0,
				(p == ball) ? rgb[1] : 0,
				(p == ball) ? rgb[2] : 0);
		}

		(void) ledscape_wait(leds);
		ledscape_draw(leds, use_frame);

		// Switch frame
		use_frame = (use_frame + 1) % 2;

		// Slow down play!
		usleep((4-speed)*5000);
	}

	// Turn off all LEDs
	for (unsigned p = 0 ; p < num_pixels; p++) ledscape_set_color(frame[use_frame], 0, p, 0, 0, 0);
	(void) ledscape_wait(leds);
	ledscape_draw(leds, use_frame);

	ledscape_close(leds);

	return EXIT_SUCCESS;
}
