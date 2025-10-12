{
 config,
 ...
}: {
	hardware.bluetooth = {
		enable = true;
	};

        networking.wireless = {
		enable = true;
		fallbackToWPA2 = false;
		networks = {
					};
	};
}

