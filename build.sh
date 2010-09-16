#!/bin/bash -e

HOST=linux-x86

ANDROIDDIR=~/froyo
ANDROIDCOMPILE=${ANDROIDDIR}/prebuilt/${HOST}/toolchain/arm-eabi-4.4.0/bin/arm-eabi-
ANDROIDBIN=${ANDROIDDIR}/out/host/${HOST}/bin

KERNELDIR=$(cd $(dirname "$0"); pwd)

PSFREEDOMDIR=${KERNELDIR}/PSFreedom

OUTPUTDIR=$(pwd)/build

#######################

status()
{
	echo -e "\033[93m[*]" $1 "\033[0m"
}

#######################

# Record where we are and come back to it
STARTDIR=$(cd $(dirname "$0"); pwd)

# Create the output directory if needed
mkdir -pv "${OUTPUTDIR}" 2>/dev/null

# Check that they checked out PSFreedom
if [ ! -e "${PSFREEDOMDIR}/Makefile" ]; then
	echo "ERROR: PSFreedom not found. Try `git-submodule update --init`" 1>&2
	exit 1
fi

# Check that they have an original.img file
if [ ! -e "${STARTDIR}/original.img" ]; then
	echo "ERROR: You must extract boot.img from your ROM and save it as original.img" 1>&2
	exit 1
fi 

# Check that ${ANDROIDDIR} exists
if [ ! -d "${ANDROIDDIR}" ]; then
	echo "ERROR: Please update build.sh with the path to your Android source tree" 1>&2
	exit 1
fi

# Check that ${ANDROIDCOMPILE} is correct for our host
${ANDROIDCOMPILE}gcc --version &>/dev/null
if [ $? -ne 0 ]; then
	echo "ERROR: The prebuilt ARM toolchain doesn't appear to work. Edit HOST in build.sh." 1>&2
	exit 1
fi

# Check that ${ANDROIDBIN} exists
if [ ! -d "${ANDROIDBIN}" ]; then
	echo "ERROR: Please build Android first" 1>&2
	exit 1
fi

#######################

status "Building Linux kernel"
cd "${KERNELDIR}"

make ARCH=arm "CROSS_COMPILE=${ANDROIDCOMPILE}"

# Copy g_android.ko if we were configured to build it
TMP=$(grep "CONFIG_USB_ANDROID" "${KERNELDIR}/.config")
if [ "${TMP}" == 'CONFIG_USB_ANDROID=m' ]; then
	status "Copying Android Debug Bridge driver"
	cp -f drivers/usb/gadget/g_android.ko "${OUTPUTDIR}"
else
	rm -f "${OUTPUTDIR}/g_android.ko"
fi

cd "${STARTDIR}"

#######################

status "Building Wi-Fi driver"
cd "${ANDROIDDIR}/system/wlan/ti/sta_dk_4_0_4_32"

rm -f "${OUTPUTDIR}/wlan.ko"
make "KERNEL_DIR=${KERNELDIR}" "CROSS_COMPILE=${ANDROIDCOMPILE}"
cp -f wlan.ko "${OUTPUTDIR}"

cd "${STARTDIR}"

#######################

status "Extracting RAM disk from original boot.img"
cd "${OUTPUTDIR}"

rm -f .extractdetails ramdisk.img
"${STARTDIR}/android-split-bootimg" "${STARTDIR}/original.img" > .extractdetails

# Pull information about the original boot.img
BASEADDR=$(printf "0x%08x" $(( $(awk -F' += +' '$1 == "kernel_addr" { print $2 }' .extractdetails) - 0x8000 )))
CMDLINE=$(awk -F' += +' '$1 == "cmdline" { print $2 }' .extractdetails)

status "Repackaging boot.img with new kernel"

"${ANDROIDBIN}/mkbootimg" --cmdline "${CMDLINE}" --base "${BASEADDR}" --kernel "${KERNELDIR}/arch/arm/boot/zImage" --ramdisk ramdisk.img -o boot.img
rm -f ramdisk.img

status "Comparing original boot.img to new"
"${STARTDIR}/android-split-bootimg" "${STARTDIR}/original.img" > .extractdetails2
diff .extractdetails .extractdetails2 || true
rm -f .extractdetails{,2} ramdisk.img

cd "${STARTDIR}"

#######################

status "Building PSFreedom"
cd "${PSFREEDOMDIR}"

rm -f "${OUTPUTDIR}/psfreedom.ko"
make ARCH=arm "CROSS_COMPILE=${ANDROIDCOMPILE}" "KDIR=${KERNELDIR}" desire
cp -f psfreedom.ko "${OUTPUTDIR}"

cd "${STARTDIR}"

#######################

status "Build successful"

