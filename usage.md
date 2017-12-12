# How to use QE+SIRIUS

After compiling with `sirius_daint_autobuild.sh`, the executable is in $START_PATH/q-e/pw.x as expected; but mind the warnings below.

## Suggested prepend script for aiida code setup:

```
export CRAY_CUDA_MPS=1 # allows sharing the GPU between MPI processes;
# set it to 0 for debugging or if you are sure that only one process per node will use the card.
export KMP_AFFINITY='granularity=fine,compact,1'
export MPICH_MAX_THREAD_SAFETY=multiple
export MKL_NUM_THREADS=1
export OMP_NUM_THREADS=2
export SDDK_BLOCK_SIZE=512 # tuning parameter for the SIRIUS Data Distribution Kit
```

## Parallelization:

Do not necessarily use 1 MPI rank per core:
- we are using OpenMP
- the bulk of the work is (our should be) done by the GPUs: more concurrent ranks are supported, but the number needs to be tweaked
  - when using AiiDA (example): `params['pw_input'].pop('automatic_parallelization')`

## Usage notes:

Add flags `-sirius -sirius_cfg [config_file]`:
- when using AiiDA (example): `params['pw_settings'] = {'cmdline':['-sirius', '-sirius_cfg', '/users/mborelli/sirius_cfg/config.json']} `

Known issue: wf_collect must be false
- AiiDA: `params['pw_parameters']['CONTROL']['wf_collect'] = False`


# To save space after compilation

You can save q-e/src/pw.x and delete everything else.

The following files can be safely removed, in theory:

```
cd SIRIUS
rm -rf doc examples libs platforms src LICENSE README.md .git .gitignore .clang-format apps
cd ..
cd q-e
rm -r archive atomic clib COUPLE CPV dev-tools Doc EPW FFTXlib GUI GWW
rm -r install LAXlib lapack-3.6.1 LAPACK iotk include License LR_Modules Modules 
rm -r pseudo PHonon PlotPhon PP PWCOND QHA README TDDFPT TODO upftools XSpectra NEB
rm -r PW/{Doc,examples,Ford}
rm -r PW/src/{*.f90,*.o,*.mod,*.a}
rm -rf .git .gitignore .travis.yml
rm -r test-suite
cd ..
```


