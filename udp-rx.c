/** \file
 *  UDP image packet receiver.
 *
 * Based on the HackRockCity LED Display code:
 * https://github.com/agwn/pyramidTransmitter/blob/master/LEDDisplay.pde
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <inttypes.h>
#include <errno.h>
#include <string.h>
#include "ledscape.h"
#include "pru.h"

int
main(
	int argc,
	char ** argv
)
{
	uint16_t port = 9999;
	uint16_t num_pixels = 256;
	uint16_t num_strips = LEDSCAPE_NUM_STRIPS;

	extern char *optarg;
	int opt;
	while ((opt = getopt(argc, argv, "p:c:d:")) != -1)
	{
		switch (opt)
		{
		case 'p':
			port = atoi(optarg);
			break;
		case 'c':
			num_pixels = atoi(optarg);
			break;
		case 'd': {
			int width=0, height=0;

			if (sscanf(optarg,"%dx%d", &width, &height) == 2) {
				num_pixels = width * height;
			} else {
				printf("Invalid argument for -d; expected NxN; actual: %s", optarg);
				exit(EXIT_FAILURE);
			}
		}
		break;
		default:
			fprintf(stderr, "Usage: %s [-p <port>] [-c <led_count> | -d <width>x<height>]\n", argv[0]);
			exit(EXIT_FAILURE);
		}
	}

	const int sock = socket(AF_INET, SOCK_DGRAM, 0);
	struct sockaddr_in addr = {
		.sin_family = AF_INET,
		.sin_addr.s_addr = INADDR_ANY,
		.sin_port = htons(port),
	};

	if (sock < 0)
		die("socket failed: %s\n", strerror(errno));

	if (bind(sock, (const struct sockaddr*) &addr, sizeof(addr)) < 0)
		die("bind port %d failed: %s\n", port, strerror(errno));

	ledscape_t * const leds = ledscape_init(num_pixels);

	fprintf(stderr, "Started LEDscape UDP receiver on port %d for %d pixels\n", port, num_pixels);
	fprintf(stderr, "WARNING: udp-rx is deprecated! opc-rx supports more options and should be used instead.\n\n");

	unsigned frame_num = 0;

	uint8_t buf[num_pixels * num_strips * 4];

	time_t last_time = time(NULL);
	int fps_counter=0;
	while (1)
	{
		const ssize_t rc = recv(sock, buf, sizeof(buf), 0);
		if (rc < 0) {
			printf("recv failed: %s\n", strerror(errno));
			continue;
		}

		ledscape_frame_t * const frame
			= ledscape_frame(leds, frame_num);

		for(uint16_t x=0 ; x < num_pixels ; x++)
		{
			for(uint16_t strip = 0 ; strip < num_strips ; strip++)
			{
				const uint8_t r = buf[strip*num_pixels*3 + x*3 + 0];
				const uint8_t g = buf[strip*num_pixels*3 + x*3 + 1];
				const uint8_t b = buf[strip*num_pixels*3 + x*3 + 2];
				ledscape_set_color(frame, strip, x, r, g, b);
			}
		}

		ledscape_wait(leds);
		ledscape_draw(leds, frame_num);

		time_t now = time(NULL);

		if (now != last_time)
		{
			printf("%d fps\n", fps_counter);
			last_time = now;
			fps_counter = 0;
		}
		fps_counter++;


		frame_num = (frame_num+1) % 2;
	}

	ledscape_close(leds);
	return 0;
}
