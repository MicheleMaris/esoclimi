#!/usr/bin/env python
#
# This is an example of python script for runnung many times the
# code, varying one parameter existing in one module .h file
# Here is the vegetation albedo in vegetation.h
#
#   GM created
#   GT 29/3/17 some small improvements
#   GM 11/4 fix small bugs, log non-convergent sim
#

'''
    Input paramters of the computational kernel:
    * simtype,
    * version,
    * simulation number
    
    
    Values of Pressure, Raddi Obliquities and Eccentricities to cycle
    
    WARNING, 0.001 e 0.005 of pressure are not working
    Pressures are epressed in times the Earth value


'''

import sys
import os
import shutil
from posix import system
import logging
from mpi4py import MPI


from fitslib import create_FITS
from thumblib import create_THUMBNAILS
from workarea import *
from runEBM import *
import numpy as np

def enum(*sequential, **named):
    '''
        simple way to emulate enumerate in python taken from the web
    '''
    enums = dict(zip(sequential, range(len(sequential))), **named)
    return type('Enum', (), enums)



Pressures=[0.01, 0.1, 0.5, 1.0, 3.0, 5.0]
Radii= [0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5]
Obliquities = [0., 15., 23.43929, 30., 45.]
Eccentricities = [ 0.0, 0.01671022, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]

Parameter_set = {'simtype': "Std", 'version': "1.1.03" }

# Directories and Files
template_dir="/home/LAVORO/Programming/Esoclimi/Devel/Templates/"
workDir = os.getcwd()

RisultatiMultipli = "RisultatiMultipli"
Database = "Database"
LogFiles = "LogFiles"
Risultati ="Risultati"
Thumbnails = "Thumbnails"
Src = "Src"
planet = "EARTH"

fits_out_base = workDir+"/Database/ESTM1.1.01-"     # base name of the FITs output
thumbs_out_base = workDir+"/Thumbnails/ESTM1.1.01-"     # base name of the FITs output
fortran_run_result="year_lat_temp_last1.tlt"        # Data File name
fits_param_file = "/esopianeti.par"
fortran_value_result="/valori.txt"



def make_work_area (_dir):
    '''
        make_work_area (_dir,_p,_ecc,_obl,_dist)
        
        create the working area dircetory and file structure coping from
        template directories
        
        p    = pressure
        ecc  = eccentricity
        obl  = obliquity
        dist = semi-major axis
        
        '''
    # here we need to catch exeptions (necessary on parallel runs)
    localSrc = _dir+"/"+Src
    os.makedirs(localSrc+"/"+Risultati)

    shutil.copytree(template_dir+"/CCM_RH60", localSrc+"/CCM_RH60")
    
    copyall(template_dir+"/ModulesDef", localSrc) # they are all empty files ????
    
    copyall(template_dir+"/Std",localSrc)
    if simtype=="VegPassive":
        copyall(template_dir+"/VegPassive",localSrc)
        copyall(template_dir+"/VegPassive/Modules/",localSrc) 
    elif simtype=="VegAlbedoFB":
        copyall(template_dir+"/VegAlbedoFB", localSrc)
        copyall(template_dir+"/VegAlbedoFB/Modules/",localSrc)

    # varying pressure on an EARTH-LIKE planet, using EARTH template
    print template_dir+"/Planets/"+planet+".h", localSrc+"/planet.h"
    shutil.copy(template_dir+"/Planets/"+planet+".h", localSrc+"/planet.h")
    if planet == "EARTH":
        shutil.copy(template_dir+"/Planets/fo_earth_DMAP.dat",localSrc+"/fo_earth_DMAP.dat")
    return



def esoclimi(Parameter_set,nSigmaCrit,nTlim,SigmaCritParams,TlimParams):
     import numpy as np

     localWorkDir    = "%s/%d/" % (workDir,Parameter_set['number'])
     localSrcDir     = "%s%s/" % (localWorkDir,Src)
     localResultDir = "%s%s/" % (localSrcDir,Risultati)
     os.chdir(workDir)
     os.mkdir(localWorkDir)
     results_string="_Press%5.3f_Ecc%4.2f_Dist%3.1f_Obl%5.3f_CO2%5.3f_GG%5.3f"%(Parameter_set['p'],Parameter_set['ecc'],Parameter_set['dist'],Parameter_set['obl'],Parameter_set['p_CO2_P'],Parameter_set['gg'])
     # initilize log file for simulation
     
     logging.info("%d => Begin computation for p=%f ecc=%f obl=%f dits=%s",Parameter_set['number'], Parameter_set['p'],Parameter_set['ecc'],Parameter_set['obl'],Parameter_set['dist'])
     make_work_area(localWorkDir)
     os.chdir(localWorkDir)
     
     logging.info("%s",os.getcwd())
     #Complile and Run
     str="python runEBM.py PRESSUREScurr.py %d %s %s > log " % (Parameter_set['number'],Parameter_set['version'],Parameter_set['simtype'])
     logging.info("%d => %s",Parameter_set['number'], str)
     setupEBM(Parameter_set,localSrcDir)
     log_file_local=open(localWorkDir+"/out.log",'w')    #open log file name is out.log
     compileEBM(localSrcDir,log_file_local)
     runEBM(localSrcDir,log_file_local)
     log_file_local.close()
    
     #now we have results. Making .fits file (REQUIRES PYFIT)
     logging.info("%d => %s", Parameter_set['number'], "Create FITS file from data")
     try:
         date = create_FITS(localResultDir+fortran_run_result,fits_out_base,localResultDir+fits_param_file)
         create_THUMBNAILS(localResultDir+fortran_run_result,thumbs_out_base, date, Parameter_set['number'])
     except:
         logging.warning("Simulation did not converge")

     #VERY IMPORTANT: CHECKING NON-CONVERGED SNOWBALL/RUNAWAY GREENHOUSE CASES 
     # (no fits produced in that case!)
     fortran_value_result_file =localResultDir+fortran_value_result
     logging.info("Open File fortran_value_result: %s", fortran_value_result_file)
     exitValue  = np.loadtxt(fortran_value_result_file)
     logging.info('ExitValue: %d', exitValue[25])
     # saving parameters for which we have SB/RG
     if np.abs(exitValue[25] + 0.5) < 0.001 : #Runaway GreenHouse
         nSigmaCrit += 1
         SigmaCritParams[0] = np.append(SigmaCritParams[0],Parameter_set['ecc'])
         SigmaCritParams[1] = np.append(SigmaCritParams[1],Parameter_set['obl'])
         SigmaCritParams[2] = np.append(SigmaCritParams[2],Parameter_set['dist'])
         SigmaCritParams[3] = np.append(SigmaCritParams[3],Parameter_set['p'])
     elif np.abs(exitValue[25] + 1.0) < 0.001: #SnowBall
         nTlim += 1
         TlimParams[0] = np.append(TlimParams[0],Parameter_set['ecc'])
         TlimParams[1] = np.append(TlimParams[1],Parameter_set['obl'])
         TlimParams[2] = np.append(TlimParams[2],Parameter_set['dist'])
         TlimParams[3] = np.append(TlimParams[3],Parameter_set['p'])

     os.chdir(localWorkDir)
     logging.debug("%d => %s",Parameter_set['number'], os.getcwd())
     logging.debug("%d => %s",Parameter_set['number'], os.listdir("."))
     
     #archiving Risults
     results_location="%s/Risultati_Press%s"%(workDir+"/"+RisultatiMultipli,results_string)
     logging.debug("%d => Archive results to: %s",Parameter_set['number'], results_location)
     archive_results(results_location,Src,Parameter_set['planet'],localResultDir)
     
     # close log file and archiving it DO We NEED THAT? YES!
     log_dir_name="%s/%s/log%s"%(workDir,LogFiles,results_string)
     logging.debug("Closing log file and archive to: %s",log_dir_name)
     archive_logs(log_dir_name,localWorkDir+"/out.log")

    #back to main dir
     os.chdir(workDir)
     CleanAllPartialResults(localWorkDir)
     return(nSigmaCrit,nTlim,SigmaCritParams,TlimParams)


if __name__ == '__main__':
    
    tags = enum('READY', 'DONE', 'EXIT', 'START')

    comm = MPI.COMM_WORLD # Communicator
    size = comm.size      # Number of processes
    rank = comm.rank      # this process
    status = MPI.Status()
#
# number of non-converged runs
    nSigmaCrit = 0
    nTlim = 0
    #parameter values for non-converged runs
    SigmaCritParams=[ np.empty(shape=0), np.empty(shape=0), np.empty(shape=0), np.empty(shape=0)]
    TlimParams= [ np.empty(shape=0), np.empty(shape=0), np.empty(shape=0), np.empty(shape=0)]
    
    # make directories where final results are stored
    if rank == 0:
        os.makedirs(RisultatiMultipli)
        os.makedirs(Database)
        os.makedirs(LogFiles)
        os.makedirs(Thumbnails)
    ##
    # open a logger (one each task==rank)
    comm.Barrier()
    logging.basicConfig(level=logging.DEBUG,
                        format='%(asctime)s %(levelname)s %(message)s',
                        filename=workDir+"/run_"+rank+".log",
                        filemode='w')

    if rank == 0:
        simulation_index = 0
        num_workers = size - 1
        closed_workers = 0
        print("Master starting with %d workers" % num_workers)
        try:
            infile = open(input_filename,"r")
        except IOError:
            print "Cannont open Input File"
            exit() ##### verify if it exists a proper way to close MPI

        for line in infile:
            input_params=np.fromstring(line, dtype=float, sep=' ')
            #print np.fromstring(line, dtype=float, sep=' ')
            Parameter_set['gg']         = 0      #geography
            Parameter_set['fo_const']   = 0.4    #ocean fraction (only for gg=0)
            Parameter_set['p_CO2_P']    = 3800   #CO2 partial pressure IN PPVM
            #check that these are consistent with p_CO2_P
            Parameter_set['TOAalbfile'] = 'CCM_RH60/ALB_g1_rh60_co2x10.txt'
            Parameter_set['OLRfile']    = 'CCM_RH60/OLR_g1_rh60_co2x10.txt'
            Parameter_set['dist'] = 1.0          # semi-major axis of planet orbit
            Parameter_set['obl'] = 25.           # planet axis inclination
            Parameter_set['ecc'] = 0.02          # eccentricity of planet orbit
            Parameter_set['number'] = numero
            Parameter_set['planet'] = planet
            Parameter_set['p'] = p
            data = comm.recv(source=MPI.ANY_SOURCE, tag=MPI.ANY_TAG, status=status)
            source = status.Get_source()
            tag = status.Get_tag()
            if tag == tags.READY: # Only at first loop
                comm.send(input_params, dest=source, tag=tags.START)
                print("FIRSTLOOP: Sending simulation %d to worker %d" % (simulation_index, source))
                simulation_index += 1
            elif tag == tags.DONE:
                results = data # collect results from worker
                print("DONE: Got data from worker %d: %s" % (source,results))
                comm.send(input_params, dest=source, tag=tags.START) #send new data to worker
                simulation_index += 1
            elif tag == tags.EXIT: # ERROR: we should not be here!!!!
                print("ERROR: Worker %d exited." % source)
                closed_workers+=1
    else: # working tasks
        name = MPI.Get_processor_name()
        print("I am a worker with rank %d on %s." % (rank, name))
        local_simulation_index = 0
        while True:
            if local_simulation_index == 0:
                local_simulation_index += 1
                comm.send(None, dest=0, tag=tags.READY)
                #print("DEBUG %d,0 BEGIN Send READY" % rank )
                inputParams = comm.recv(source=0, tag=MPI.ANY_TAG, status=status)
                #print("DEBUG %d,0 BEGIN receive" % rank )
                tag = status.Get_tag()
                print("Receive simulation on worker %d from  0"  % (rank))
                if tag == tags.START:
                    print("DEBUG %d,0: begin computation" % (rank))
                    esoclimi(numero,ecc,obl,dist,p)
                    result = "HO FATTO"
                    comm.send(result, dest=0, tag=tags.DONE)
                #print("DEBUG %d,0 BEGIN send" % rank )
                elif tag == tags.EXIT:
                    comm.send(None, dest=0, tag=tags.EXIT) # chiudi task mpi e esci
            else:
                #print("DEBUG %d,0 LOOP begin" % rank )
                local_simulation_index += 1
                inputParams = comm.recv(source=0, tag=MPI.ANY_TAG, status=status)
                tag = status.Get_tag()
                if tag == tags.START:
                    print("DEBUG %d,0: loop computation" % (rank))
                    esoclimi(numero,ecc,obl,dist,p)
                    result = "HO FATTO"
                    comm.send(result, dest=0, tag=tags.DONE)
                elif tag == tags.EXIT:
                        break
        comm.send(None, dest=0, tag=tags.EXIT)







    print 'nSigmaCrit, nTlim: ', nSigmaCrit,  nTlim


    print '\n\n\n'
    print 'nSigmaCrit (Runaway Greenhouse), nTlim (Snowball): ', nSigmaCrit,  nTlim
    print 'Fractions: ', 1.0*nSigmaCrit/numero, 1.0*nTlim/numero
    print '\n Overall number and fraction of non-converged inhabitable cases: ', nSigmaCrit+nTlim, 1.0*(nSigmaCrit+nTlim) / numero
    print '\n Total number of runs: ',numero

    #recording these on a file!
    f=open('NonConverged.dat','w')
    f.write('nSigmaCrit (Runaway Greenhouse), nTlim (Snowball): %d %d \n' % (nSigmaCrit,  nTlim) )
    f.write('Fractions: %e %e\n' % (1.0*nSigmaCrit/numero, 1.0*nTlim/numero) )
    f.write('Overall number and fraction of non-converged inhabitable cases: %d %e \n' %(nSigmaCrit+nTlim, 1.0*(nSigmaCrit+nTlim) / numero))
    f.write('Total number of runs: %d\n' % numero)
    f.close()
    
    with open('SnowBall-Params.dat','w') as f:
        for l in np.matrix(TlimParams).T:
            np.savetxt(f,l,'%e ')

    with open('RunawayGreenhouse-Params.dat','w') as f:
        for l in np.matrix(SigmaCritParams).T:
            np.savetxt(f,l,'%e ')



