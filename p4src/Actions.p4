// This file contains common actions to the ingress and egress pipelines.


/**
 * Send the packet to the CPU port.
 */
action Send_to_cpu()
{ clone( CloneType.I2E, CPU_MIRROR_SESSION_ID ); }
	
	
/**
 * Indicates that a packet is dropped by setting the
 * output port to the DROP_PORT
 */
action Drop()
{ mark_to_drop(); }
