# Tiny Flasher
A simple and tiny flashing utility for OS X

![screenshot](docs/img/screenshot.png?raw=1)

## Features
* Tiny
* Flashes USB and SD card images directly to disks
* Creates Windows installation USB drives (EFI only)<sup>1</sup>

<sub>**1** These are not intended for use on Apple hardware. If you need Apple hardware support, use Boot Camp.</sub>

## Downloads
Downloads can be found on the [releases](https://github.com/xxmicloxx/TinyFlasher/releases) page.

## Building
In order to use your own build of the app, you first need to remove the helper tool. This is because the app signature is checked whenever you want to access the helper, and since you cannot build using my signature, you will be denied access. You can remove the old helper tool by simply running the `uninstallHelper.command` file in this repo.

Afterwards, you need to change the signature info in `Helper-Info.plist` and `Info.plist`. This can be done automatically using `SMJobBlessUtil.py` provided by Apple themselves. However, before you do that, make sure that you have built the app in Xcode at least once - do not run the built app yet, though. Also make sure that you've selected a valid signing certificate for both the Tiny Flasher target and the helper target in Xcode.

You can download the helper file required for the following steps [here](https://developer.apple.com/library/archive/samplecode/SMJobBless/Listings/SMJobBlessUtil_py.html). In order to use the tool, first type `./SMJobBlessUtil.py setreq ` in a terminal in the directory of the downloaded file (notice the space after `setreq`).

Now, drag `Tiny Flasher.app` from the `Products` folder in Xcode to the terminal, which will paste the path to the file. Insert another space, then drag `ImageWriter/Info.plist` from Xcode into the terminal. Add another space and drag `ImageWriterHelper/Helper-Info.plist` to the terminal. Now, press return.

The utility will change the information in the plist files and therefore allow you to run your own builds using your own signature. After rebuilding the project once more, you should now be able to run your own builds.
