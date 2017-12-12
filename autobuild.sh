# QE+SIRIUS (only PW) automatic compilation script for Piz Daint
# Author: Marco Borelli, with a lot of help from Anton Kozhevnikov

#######################################################################

# Parameters:

#SIRIUS_BRANCH=master  # most stable
SIRIUS_BRANCH=develop
QE_BRANCH=sirius  # this shouldn't change
#SIRIUS_PLATFORM_FILE=platform.XC50.GNU.MKL.CUDA.noMAGMA.json
SIRIUS_PLATFORM_FILE=platform.XC50.GNU.MKL.CUDA.noMAGMA.noELPA.json
SIRIUS_DEBUG_SYMBOLS="yes"  # "yes" or "no"
SIRIUS_MAKE_APPS="no"       # "yes" or "no"

#######################################################################

function escape_slashes {
    sed 's/\//\\\//g' 
}

START_PATH=$PWD

echo "----- Building QE+SIRIUS -----"
echo "Starting path: $START_PATH"
echo "QE branch: $QE_BRANCH; SIRIUS branch: $SIRIUS_BRANCH" 
echo "SIRIUS platform file: $SIRIUS_PLATFORM_FILE"
echo "Compiling SIRIUS with '-Og -g': $SIRIUS_DEBUG_SYMBOLS"
echo "Also compiling SIRIUS mini-apps: $SIRIUS_MAKE_APPS"
echo "------------------------------"

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

# clone SIRIUS
git clone --depth=1 --single-branch --branch $SIRIUS_BRANCH https://github.com/electronic-structure/SIRIUS
cd SIRIUS

# configure
python configure.py $SIRIUS_PLATFORM_FILE

# compile with -g if requested
if [ $SIRIUS_DEBUG_SYMBOLS == "yes" ]; then
    sed -i "s/BASIC_CXX_OPT = -O3/BASIC_CXX_OPT = -Og -g/g" make.inc
fi

# make SIRIUS
if [ $SIRIUS_MAKE_APPS == "no" ]; then
  make packages sirius
else
  make all
fi

# clone the SIRIUS-enabled fork of QuantumESPRESSO, correct branch
cd $START_PATH
git clone --depth=1 --single-branch --branch sirius https://github.com/electronic-structure/q-e.git
cd q-e

# configure
./configure ARCH=cray-xt --enable-openmp --with-scalapack

# change some stuff in q-e/make.inc, but first get the list of libraries for linking with the SIRIUS Fortran code
cd $START_PATH/SIRIUS/src
SIRIUS_LD_LIBS=$(make showlibs | sed 's/List of libraries for linking with the Fortran code://g')
cd $START_PATH/q-e
#sed -i "/TEXT_TO_BE_REPLACED/c\REPLACEMENT" file
sed -i "/DFLAGS         =/c\DFLAGS         =  -D__OPENMP -D__FFTW -D__OLDXML -D__MPI -D__SCALAPACK -D__SIRIUS -I$(echo ${START_PATH}/SIRIUS/src | escape_slashes)" make.inc
sed -i "s/gfortran/ftn/g" make.inc
sed -i "/LD_LIBS        =/c\LD_LIBS        = $(echo ${SIRIUS_LD_LIBS} | escape_slashes)" make.inc
sed -i "/BLAS_LIBS      =/c\BLAS_LIBS      =" make.inc
sed -i "/LAPACK_LIBS    =/c\LAPACK_LIBS    =" make.inc
sed -i "/BLAS_LIBS_SWITCH =/c\BLAS_LIBS_SWITCH = external" make.inc
sed -i "/LAPACK_LIBS_SWITCH =/c\LAPACK_LIBS_SWITCH = external" make.inc

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
if [[ $(nm pw.x | grep -i sirius) -gt "100" ]]; then
    echo "OK: statically compiled with SIRIUS";
else
    echo "WARNING: not compiled with SIRIUS ??";
fi


# ---- DONE ----

