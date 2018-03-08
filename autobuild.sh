# QE+SIRIUS (only PW) automatic compilation script for Piz Daint
# Author: Marco Borelli, with a lot of help from Anton Kozhevnikov

#######################################################################

set -e

# Parameters:

#SIRIUS_BRANCH=master  # most stable
SIRIUS_BRANCH=develop
QE_BRANCH=sirius  # this shouldn't change
SIRIUS_PLATFORM_FILE=qe_sirius_on_daint/platform.XC50.GNU.MKL.CUDA.noMAGMA.json
#SIRIUS_PLATFORM_FILE=qe_sirius_on_daint/platform.XC50.GNU.MKL.CUDA.noMAGMA.noELPA.json
SIRIUS_DEBUG_SYMBOLS="yes"
SIRIUS_DEBUG_MODE="no"
SIRIUS_GLIBCXX_DEBUG="no"
SIRIUS_MAKE_APPS="no"

#######################################################################

function escape_slashes {
  sed 's/\//\\\//g'
}

START_PATH=$PWD

echo "----- Building QE+SIRIUS -----"
echo "Starting path: $START_PATH"
echo "QE branch: $QE_BRANCH"
echo "SIRIUS branch: $SIRIUS_BRANCH"
echo "SIRIUS platform file: $SIRIUS_PLATFORM_FILE"
echo "Compiling SIRIUS with '-Og -g': $SIRIUS_DEBUG_SYMBOLS"
echo "Compiling SIRIUS in debug/unoptimized mode: $SIRIUS_DEBUG_MODE"
echo "Compiling SIRIUS with -D_GLIBCXX_DEBUG: $SIRIUS_GLIBCXX_DEBUG"
echo "Also compiling SIRIUS mini-apps: $SIRIUS_MAKE_APPS"
echo "------------------------------"
printf "Press ENTER to proceed"
read REPLY

# Check that the platform file exists
if [ ! -f $SIRIUS_PLATFORM_FILE ]; then
    echo "Missing platform file for SIRIUS: exiting."
    exit
fi

# load/unload correct modules
module unload PrgEnv-cray
module load PrgEnv-gnu  # GNU programming environment (incl. compiler)
module unload cray-libsci
module load intel       # to get MKL
module load cray-hdf5
module load cudatoolkit
module list

ftn --version
#GNU Fortran (GCC) 5.3.0 20151204 (Cray Inc.)

# find the location of installed ELPA
export ELPA_ROOT=$(spack location -i elpa@2017+openmp %gcc)
export ELPA_INCLUDE_PATH=$(echo ${ELPA_ROOT}/include/elpa_openmp*/elpa/)
export ELPA_LIB_PATH=${ELPA_ROOT}/lib/
if [[ -z ${ELPA_ROOT// } ]]; then
  echo "ELPA root path empty"
  exit
fi
if [[ ! -f ${ELPA_INCLUDE_PATH}/elpa_constants.h ]]; then
  echo "\"elpa_constants.h\" not found in ${ELPA_INCLUDE_PATH}"
  exit
fi
if [[ ! -f ${ELPA_LIB_PATH}/libelpa_openmp.a ]]; then
  echo "\"libelpa.a\" not found in ${ELPA_LIB_PATH}"
  exit
fi
echo "ELPA found at: $ELPA_ROOT"

# clone SIRIUS
git clone --depth=1 --single-branch --branch $SIRIUS_BRANCH https://github.com/electronic-structure/SIRIUS
cp $SIRIUS_PLATFORM_FILE SIRIUS/platform_file.json
cd SIRIUS

# configure
python configure.py platform_file.json

# compile with -g if requested
if [ $SIRIUS_DEBUG_SYMBOLS == "yes" ]; then
    sed -i "s/BASIC_CXX_OPT = -O3/BASIC_CXX_OPT = -Og -g -ggdb/g" make.inc
fi

# compile in debug mode if requested (-O1 -g -ggdb, and without -DNDEBUG)
if [ $SIRIUS_DEBUG_MODE == "yes" ]; then
    sed -i "s/debug = false/debug = true/" make.inc
fi

# add _D_GLIBCXX_DEBUG if requested
if [ $SIRIUS_GLIBCXX_DEBUG == "yes" ]; then
    sed -i "s/BASIC_CXX_OPT =/BASIC_CXX_OPT = -D_GLIBCXX_DEBUG /g" make.inc
fi

# Unfortunately we also need to patch make.inc for the ELPA paths
sed -i 's/$(ELPA_ROOT_PLACEHOLDER)\/elpa/'"$(echo ${ELPA_INCLUDE_PATH} | escape_slashes)/g" make.inc
sed -i 's/$(ELPA_ROOT_PLACEHOLDER)\/.libs/'"$(echo ${ELPA_LIB_PATH} | escape_slashes)/g" make.inc

# make SIRIUS
if [ $SIRIUS_MAKE_APPS == "no" ]; then
  make packages sirius
else
  make all
fi

# clone the SIRIUS-enabled fork of QuantumESPRESSO, correct branch
cd $START_PATH
git clone --depth=1 --single-branch --branch $QE_BRANCH https://github.com/electronic-structure/q-e.git
#git clone --depth=1 --single-branch --branch $QE_BRANCH git@github.com:borellim/q-e.git
printf "Press ENTER to proceed"
read REPLY
cd q-e
./configure ARCH=cray-xt --enable-openmp --with-scalapack

# change some stuff in q-e/make.inc, but first get the list of libraries for linking with the SIRIUS Fortran code
cd $START_PATH/SIRIUS/src
SIRIUS_LD_LIBS=$(make showlibs | sed 's/List of libraries for linking with the Fortran code://g')
cd $START_PATH/q-e
#sed -i "/TEXT_TO_MATCH/c\REPLACEMENT" file
# NB: c\ means to replace a whole line
sed -i "/DFLAGS         =/c\DFLAGS         =  -D__OPENMP -D__FFTW -D__OLDXML -D__MPI -D__SCALAPACK -D__SIRIUS -I$(echo ${START_PATH}/SIRIUS/src | escape_slashes)" make.inc  # NB: -D__ELPA should also be here, but it's temporarily broken!
sed -i "s/gfortran/ftn/g" make.inc
sed -i "/LD_LIBS        =/c\LD_LIBS        = $(echo ${SIRIUS_LD_LIBS} | escape_slashes)" make.inc
sed -i "/BLAS_LIBS      =/c\BLAS_LIBS      =" make.inc
sed -i "/LAPACK_LIBS    =/c\LAPACK_LIBS    =" make.inc
sed -i "/BLAS_LIBS_SWITCH =/c\BLAS_LIBS_SWITCH = external" make.inc
sed -i "/LAPACK_LIBS_SWITCH =/c\LAPACK_LIBS_SWITCH = external" make.inc
# IMPORTANT NOTES FOR COMPILING ON OTHER SYSTEMS!!:
# - You may also need to add "-lmpi_cxx" to LD_LIBS, because the linker needs both the Fortran and C++ MPI bindings.
#   By default, the linker is mpif90, which already has the Fortran MPI bindings, but not the C++ ones.
#   On Daint, the ftn wrapper appears to also have the C++ bindings.
# - The names of the compilers and the linker might already be fine as autodetected (they are on my laptop).

# make PW
make pw

# check that it is using the correct dynamic libraries (nvidia, cublas, ..)
cd $START_PATH/q-e/PW/src  # q-e/bin should be the same
if [[ ( $(ldd pw.x | grep cudart | wc -l) -gt "0" ) && \
      ( $(ldd pw.x | grep cublas | wc -l) -gt "0" ) ]]; then
    echo "OK: detected dependency on CUDA dynamic libraries";
else
    echo "WARNING: missing dependency on CUDA dynamic libraries: not compiled with CUDA ??";
fi
# check that it was statically linked with SIRIUS
if [[ $(nm pw.x | grep -i sirius | wc -l) -gt "100" ]]; then
    echo "OK: statically compiled with SIRIUS";
else
    echo "WARNING: not compiled with SIRIUS ??";
fi


# ---- DONE ----

