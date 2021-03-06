cimport cython
cimport cython
import photonHit_pb2
import ratchromadata_pb2
import numpy as np
cimport numpy as np

import chroma.api as api
api.use_cuda()
from chroma.sim import Simulation
from chroma.event import Photons
from chroma.gpu.photon_fromstep import GPUPhotonFromSteps
import chroma.event

from uboone import uboone

import time
import message_pack_cpp #refers to external c++ code. 


DTYPEINT = np.int32
ctypedef np.int_t DTYPEINT_t
DTYPEFLOAT32 = np.float32
ctypedef np.float32_t DTYPEFLOAT32_t
DTYPEUINT16 = np.uint16
ctypedef np.uint16_t DTYPEUINT16_t

det = uboone()

sim = Simulation(det,geant4_processes=0,nthreads_per_block = 128, max_blocks = 1024)

cdef extern from "photonMessage.hh" namespace "Message_Packing":
     void C_MessagePack(int* PMTArr, float* TimeArr, float* WaveArr, float* PosArr, float* DirArr, float* PolArr, int nphotons)
     void shipBack()
     str returnPhits()
     void killSocket()

@cython.boundscheck(False)
@cython.wraparound(False)
def MessagePack(np.ndarray[int, ndim = 1, mode = "c"] PMT, np.ndarray[float, ndim = 1, mode = "c"] Time, np.ndarray[float, ndim = 1, mode = "c"]Wavelengths, np.ndarray[float, ndim = 2, mode = "c"] Pos, np.ndarray[float, ndim = 2, mode = "c"] Dir ,np.ndarray[float, ndim = 2, mode = "c"] Pol,int nphotons):
        C_MessagePack(&PMT[0],&Time[0],&Wavelengths[0],&Pos[0,0],&Dir[0,0],&Pol[0,0], nphotons)
def sendPhotons():
        shipBack()
def killCPPSocket():
        killSocket()
@cython.boundscheck(False)
@cython.wraparound(False)
def MakePhotonMessage(chromaData):
    photons = GenScintPhotons(chromaData)
    events = sim.simulate(photons, keep_photons_end=True, max_steps=2000)
    stime = time.clock()
    cdef float const1 = float((2*(np.pi)*(6.582*(10**-16))*(299792458.0)))
    cdef float const2 = (4.135667516 * (10**-21))
    cdef int n, f
    cdef np.ndarray[np.int32_t,ndim = 1] channelhit	
    cdef np.ndarray[unsigned int,ndim = 1] detected_photons
    phits = photonHit_pb2.PhotonHits()
    for ev in events:
        print "!!!!!!!!!!!!!!!EVENT!!!!!!!!!!!!!!"
        detected_photons = ev.photons_end.flags[:] & chroma.event.SURFACE_DETECT
        channelhit = np.zeros(len(detected_photons), dtype = np.int32)
        channelhit[:] = det.solid_id_to_channel_index[ det.solid_id[ev.photons_end.last_hit_triangles[:] ] ]
        phits.count = int(np.count_nonzero(detected_photons))
        detected_photons_count = len(detected_photons)
        # for n,f in enumerate(detected_photons):
        #     if f==0:
        #         continue
        #     else:
        #         pass
            # aphoton = phits.photon.add()
            # aphoton.PMTID = int(channelhit[n])
            # aphoton.Time = float(ev.photons_end.t[n])
            # aphoton.KineticEnergy = (const1/float((ev.photons_end.wavelengths[n])))
            # aphoton.posX = float(ev.photons_end.pos[n,0])
            # aphoton.posY = float(ev.photons_end.pos[n,1])
            # aphoton.posZ = float(ev.photons_end.pos[n,2])
            # #px = |p|*cos(theta) = (h / lambda)*(<u,v> / |u||v|) = (h / lambda)*(u1 / |u|), etc.
            # #turns out we don't need to to this... px = |p|*phat = (h / lambda) * (dir[n,0]...etc.
            # aphoton.momX = (const2 /float((ev.photons_end.wavelengths[n]))) * float((ev.photons_end.dir[n,0]))
            # aphoton.momY = (const2 /float((ev.photons_end.wavelengths[n]))) * float((ev.photons_end.dir[n,1]))
            # aphoton.momZ = (const2 /float((ev.photons_end.wavelengths[n]))) * float((ev.photons_end.dir[n,2]))
            # aphoton.polX = float(ev.photons_end.pol[n,0])
            # aphoton.polY = float(ev.photons_end.pol[n,1])
            # aphoton.polZ = float(ev.photons_end.pol[n,2])
            # aphoton.origin = photonHit_pb2.Photon.CHROMA 
            
            #attempt to use external c++ function:
        stime = time.clock()
        MessagePack(channelhit,ev.photons_end.t,ev.photons_end.wavelengths,ev.photons_end.pos,ev.photons_end.dir, ev.photons_end.pol,detected_photons_count)
        print "pack time:",(time.clock()-stime)
    etime = time.clock()
    print "TIME TO MAKE MESSAGE: ",(etime-stime)
    #return phits
    #instead of returning phits, we will try to have c++ send the proto obj.

@cython.boundscheck(False)
@cython.wraparound(False)
def GenScintPhotons(protoString):
    stime = time.clock()
    cdef int nsphotons,stepPhotons,i,j
    cdef np.ndarray[DTYPEFLOAT32_t,ndim = 2] pos, pol, dir
    cdef np.ndarray[DTYPEFLOAT32_t,ndim = 1] wavelengths, t, dphi, dcos, phi, rArr
    nsphotons = 0
    for i,sData in enumerate(protoString.stepdata):
        nsphotons += sData.nphotons
    print "NSPHOTONS: ",nsphotons

    """THIS BLOCK USES CPU PHOTON GEN"""
    pos = np.zeros((nsphotons,3),dtype=np.float32)
    pol = np.zeros_like(pos)
    t = np.zeros(nsphotons, dtype=np.float32)
    wavelengths = np.empty(nsphotons, np.float32)
    wavelengths.fill(128.0)
    dphi = np.random.uniform(0,2.0*np.pi, nsphotons).astype(np.float32)
    dcos = np.random.uniform(-1.0, 1.0, nsphotons).astype(np.float32)
    phi = np.random.uniform(0,2.0*np.pi, nsphotons).astype(np.float32)
    dir = np.array( zip( np.sqrt(1-dcos[:]*dcos[:])*np.cos(dphi[:]), np.sqrt(1-dcos[:]*dcos[:])*np.sin(dphi[:]), dcos[:] ), dtype=np.float32 )
    pol[:,0] = np.cos(phi)
    pol[:,1] = np.sin(phi)
    rArr = np.random.uniform(0,1.0, nsphotons).astype(np.float32) #random array to sample probability of prompt or late
    stepPhotons = 0
    for i,sData in enumerate(protoString.stepdata):
        #instead of appending to array every loop, the full size (nsphotons x 3) is allocated to begin, then 
        #values are filled properly by incrementing stepPhotons.
        for j in xrange(stepPhotons, (stepPhotons+sData.nphotons)):
            pos[j,0] = np.random.uniform(sData.step_start_x,sData.step_end_x)
            pos[j,1] = np.random.uniform(sData.step_start_y,sData.step_end_y)
            pos[j,2] = np.random.uniform(sData.step_start_z,sData.step_end_z)
        #moved pol outside of the loop. saved ~3 seconds in event loop time. 
        # for j in xrange(stepPhotons, (stepPhotons+sData.nphotons)):
        #     pol[j,0] = np.random.uniform(0,((1/3.0)**.5))
        #     pol[j,1] = np.random.uniform(0,((1/3.0)**.5))
        #     pol[j,2] = ((1 - pol[j,0]**2 - pol[j,1]**2)**.5)
        for j in xrange(stepPhotons, (stepPhotons+sData.nphotons)):
                if rArr[j] < 0.6: 
                        #prompt
                        t[j] = (np.random.exponential(6.0) + (sData.step_end_t-sData.step_start_t))
                        #note that numpy documentation is wrong about how scale parameter is used (need beta instead of 1/beta)
                else:
                        #late
                        t[j] = (np.random.exponential(1500.0) + (sData.step_end_t-sData.step_start_t))
        stepPhotons += sData.nphotons
    etime = time.clock()
    print "TIME TO GEN PHOTONS: ",(etime-stime)
    return Photons(pos = pos, pol = pol, t = t, dir = dir, wavelengths = wavelengths)

    """THIS BLOCK USES GPU PHOTON GEN"""
    # cdef np.ndarray[DTYPEFLOAT32_t,ndim = 2] step_data
    # step_data = np.zeros( (len(protoString.stepdata), 10 ), dtype=np.float32 )
    # stepPhotons = 0
    # for i,sData in enumerate(protoString.stepdata):
    #     #instead of appending to array every loop, the full size (nsphotons x 3) is allocated to begin, then 
    #     #values are filled properly by incrementing stepPhotons.
    #     step_data[i,0] = sData.step_start_x
    #     step_data[i,1] = sData.step_start_y
    #     step_data[i,2] = sData.step_start_z
    #     step_data[i,3] = sData.step_end_x
    #     step_data[i,4] = sData.step_end_y
    #     step_data[i,5] = sData.step_end_z
    #     step_data[i,6] = sData.nphotons
    #     step_data[i,7] = 0.6
    #     step_data[i,8] = 6.0
    #     step_data[i,9] = 1500.0

    # step_photons = GPUPhotonFromSteps( step_data )

    # photons = step_photons.get()
    # etime = time.time()
    # print "TIME TO GEN PHOTONS: ",(etime-stime)
    # return photons




