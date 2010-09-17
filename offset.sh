#!/bin/bash -e

HOST=linux-x86

ANDROIDDIR=~/froyo
ANDROIDCOMPILE=${ANDROIDDIR}/prebuilt/${HOST}/toolchain/arm-eabi-4.4.0/bin/arm-eabi-
ANDROIDBIN=${ANDROIDDIR}/out/host/${HOST}/bin

KERNELDIR=$(cd $(dirname "$0"); pwd)

OUTPUTDIR=$(pwd)/build

PATCHTEMPLATE=$(pwd)/PSFreedom_patch_template.diff
PATCHOUTPUT=${OUTPUTDIR}/PSFreedom_patch.diff

# C file where struct usb_info is defined (relative to ${KERNELDIR})
CFILE=drivers/usb/gadget/msm72k_udc.c

# Object file the C file will be compiled into
OFILE=drivers/usb/gadget/msm72k_udc.o

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

# Check that "PSFreedom_patch.diff" is in ${STARTDIR}
if [ ! -e "${PATCHTEMPLATE}" ]; then
	echo "ERROR: Patch template file not found." 1>&2
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

# Check that ${KERNELDIR}/${CFILE} exists
if [ ! -e "${KERNELDIR}/${CFILE}" ]; then
	echo "ERROR: Couldn't find ${CFILE} in the kernel source tree. Is it right?" 1>&2
	exit 1
fi

#######################

status "Appending code to $(basename "${CFILE}")"

cp -f "${KERNELDIR}/${CFILE}" "${OUTPUTDIR}/offset.c"
cat <<EOF >>"${OUTPUTDIR}/offset.c"
unsigned long x = 0x3733334C;
unsigned long y = offsetof(struct usb_info, gadget) - offsetof(struct usb_info, addr);
EOF

status "Compiling"
cd "${KERNELDIR}"

eval $(make ARCH=arm "CROSS_COMPILE=${ANDROIDCOMPILE}" MAKE="make --dry-run -W \"${CFILE}\"" "${OFILE}" \
  | tail -n 1 \
  | awk 'BEGIN { RS = "[ \t]*;[ \t]*" } $1 == "'"${ANDROIDCOMPILE}gcc"'" { print $0 }' \
  | sed 's,'"${OFILE}"','"${OUTPUTDIR}/offset"',' \
  | sed 's,'"${CFILE}"','"${OUTPUTDIR}/offset.c"',' \
)

rm -f "${OUTPUTDIR}/offset.c"
cd "${STARTDIR}"

#######################

status "Extracting offset from binary"

OFFSET=$(python <<EOF
import struct
data = file("${OUTPUTDIR}/offset").read()
_, offset = struct.unpack_from("<LL", data[data.find("L337"):])
print offset
EOF
)

rm -f "${OUTPUTDIR}/offset"

#######################

status "Generating patch file for ${OFFSET}-byte offset"

sed 's/+#define UI_GADGET_OFFSET [0-9][0-9]*/+#define UI_GADGET_OFFSET '"${OFFSET}"'/g' < "${PATCHTEMPLATE}" > "${PATCHOUTPUT}."
mv -f "${PATCHOUTPUT}"{.,}

status "Patch generation successful"
