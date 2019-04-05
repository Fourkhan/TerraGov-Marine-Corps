//MEDBOT
//MEDBOT PATHFINDING
//MEDBOT ASSEMBLY

// TODO: Add calls to check if injections are safe
// TODO: Build data structure to acct for different meds
// TODO: Build code to pull reagants from storage
// TODO: Move all boilerplate -> nextPatient()


/obj/machinery/bot/medbot
	name = "Medibot"
	desc = "A little medical robot. It looks somewhat underwhelmed."
	icon = 'icons/obj/aibots.dmi'
	icon_state = "medibot0"
	density = 0
	anchored = 0
	health = 20
	maxhealth = 20
	req_access = list(ACCESS_MARINE_MEDBAY)
	var/stunned = 0   // It can be stunned by tasers. Delicate circuits.
	//var/emagged = 0 // Not currently implemented on TGMC
	var/list/botcard_access = list(ACCESS_MARINE_MEDBAY)
	var/obj/item/reagent_container/glass/reagent_glass = null //Can be set to draw from this for reagents.
	var/skin = null     //Set to "tox", "ointment" or "o2" for the other two firstaid kits.
	var/path[] = new()
	var/oldloc = null
	
	// BOT STATE 

	var/frustration = 0           // Used to (relatively) keep the bot in one place 
	var/currently_healing = 0     // Whether the bot is currently medicating a patient
	var/last_found = 0            // Last worldtime we found a patient 
	var/mob/living/carbon/patient = null       // Current patient
	var/mob/living/carbon/oldpatient = null    // Last patient 
	var/list/patient_damagetypes = list() // List of patient's damagetypes 

	// BOT BEHAVIOR 
	
	var/safety_checks = 1         // Checks if injection will OD before performing
	var/injection_amount = 15     // Amount injected by treatment routine
	var/heal_threshold = 20       // Minimum damage to administer treatment
	var/use_beaker = 0            // Attempt to use reagents in beaker
	var/declare_treatment = 0     // Ping medical as we treat patients?
	var/shut_up = 0               // self explanatory :)
	var/last_newpatient_speak = 0 // Don't spam the "HEY I'M COMING" messages

	// List of possible damagetypes
	// Virus is included for compatibility
	var/list/damagetypes = {"brute","burn","oxy","tox","virus"}
	
	// List of medicines by preference (will check beaker, then synthesizer)
	var/list/medicine_directory = list()
	medicine_directory["brute"] = {"bicardidine","tricordrazine"}
	medicine_directory["burn"] = list("dermaline", "kelotane", "tricordrazine")
	medicine_directory["oxy"] = list("dexalinplus", "dexalin", "tricordrazine")
	medicine_directory["tox"] = list("dylovene", "tricordrazine")
	medicine_directory["virus"] = list("spaceacillin")

	// Medicines that can be produced by the medibot's internal synthesizer 
	var/list/can_synthesize = {"tricordrazine, spaceacillin"}


/obj/machinery/bot/medbot/Initialize()
	. = ..()
	src.icon_state = "medibot[src.on]"

	if(src.skin)
		src.overlays += image('icons/obj/aibots.dmi', "medskin_[src.skin]")

	src.botcard = new /obj/item/card/id(src)
	botcard.access = ALL_MARINE_ACCESS
	start_processing()

/obj/machinery/bot/medbot/turn_on()
	. = ..()
	src.icon_state = "medibot[src.on]"
	src.updateUsrDialog()

/obj/machinery/bot/medbot/turn_off()
	..()
	src.patient = null
	src.oldpatient = null
	src.oldloc = null
	src.path = new()
	src.currently_healing = 0
	src.last_found = world.time
	src.icon_state = "medibot[src.on]"
	src.updateUsrDialog()

/obj/machinery/bot/medbot/attack_paw(mob/user as mob)
	return attack_hand(user)

/obj/machinery/bot/medbot/attack_hand(mob/user as mob)
	. = ..()
	if (.)
		return
	var/dat
	dat += "<TT><B>Automatic Medical Unit v1.0</B></TT><BR><BR>"
	dat += "Status: <A href='?src=\ref[src];power=1'>[src.on ? "On" : "Off"]</A><BR>"
	dat += "Maintenance panel is [src.open ? "opened" : "closed"]<BR>"
	dat += "Beaker: "
	if (src.reagent_glass)
		dat += "<A href='?src=\ref[src];eject=1'>Loaded \[[src.reagent_glass.reagents.total_volume]/[src.reagent_glass.reagents.maximum_volume]\]</a>"
	else
		dat += "None Loaded"
	dat += "<br>Behaviour controls are [src.locked ? "locked" : "unlocked"]<hr>"
	if(!src.locked || issilicon(user))
		dat += "<TT>Healing Threshold: "
		dat += "<a href='?src=\ref[src];adj_threshold=-10'>--</a> "
		dat += "<a href='?src=\ref[src];adj_threshold=-5'>-</a> "
		dat += "[src.heal_threshold] "
		dat += "<a href='?src=\ref[src];adj_threshold=5'>+</a> "
		dat += "<a href='?src=\ref[src];adj_threshold=10'>++</a>"
		dat += "</TT><br>"

		dat += "<TT>Injection Level: "
		dat += "<a href='?src=\ref[src];adj_inject=-5'>-</a> "
		dat += "[src.injection_amount] "
		dat += "<a href='?src=\ref[src];adj_inject=5'>+</a> "
		dat += "</TT><br>"

		dat += "<TT>OD Protection: "
		dat += "<b>[safety_checks ? "On" : "Off"]</b> : "
		dat += "<a href='?src=\ref[src];togglesafety=1'>Toggle?</a>"
		dat += "</TT><br>"

		dat += "Reagent Source: "
		dat += "<a href='?src=\ref[src];use_beaker=1'>[src.use_beaker ? "Loaded Beaker (When available)" : "Internal Synthesizer"]</a><br>"

		dat += "Treatment report is [src.declare_treatment ? "on" : "off"]. <a href='?src=\ref[src];declaretreatment=[1]'>Toggle</a><br>"

		dat += "The speaker switch is [src.shut_up ? "off" : "on"]. <a href='?src=\ref[src];togglevoice=[1]'>Toggle</a><br>"

	user << browse("<HEAD><TITLE>Medibot v1.0 controls</TITLE></HEAD>[dat]", "window=automed")
	onclose(user, "automed")
	return

/obj/machinery/bot/medbot/Topic(href, href_list)
	if(..())
		return
	usr.set_interaction(src)
	src.add_fingerprint(usr)
	if ((href_list["power"]) && (src.allowed(usr)))
		if (src.on)
			turn_off()
		else
			turn_on()

	else if((href_list["adj_threshold"]) && (!src.locked || issilicon(usr)))
		var/adjust_num = text2num(href_list["adj_threshold"])
		src.heal_threshold += adjust_num
		if(src.heal_threshold < 5)
			src.heal_threshold = 5
		if(src.heal_threshold > 75)
			src.heal_threshold = 75

	else if((href_list["adj_inject"]) && (!src.locked || issilicon(usr)))
		var/adjust_num = text2num(href_list["adj_inject"])
		src.injection_amount += adjust_num
		if(src.injection_amount < 5)
			src.injection_amount = 5
		if(src.injection_amount > 15)
			src.injection_amount = 15

	else if((href_list["togglesafety"]) && (!src.locked || issilicon(usr)))
		safety_checks = !safety_checks

	else if((href_list["use_beaker"]) && (!src.locked || issilicon(usr)))
		src.use_beaker = !src.use_beaker

	else if (href_list["eject"] && (!isnull(src.reagent_glass)))
		if(!src.locked)
			src.reagent_glass.loc = get_turf(src)
			src.reagent_glass = null
		else
			to_chat(usr, "<span class='notice'>You cannot eject the beaker because the panel is locked.</span>")

	else if ((href_list["togglevoice"]) && (!src.locked || issilicon(usr)))
		src.shut_up = !src.shut_up

	else if ((href_list["declaretreatment"]) && (!src.locked || issilicon(usr)))
		src.declare_treatment = !src.declare_treatment

	src.updateUsrDialog()
	return

/obj/machinery/bot/medbot/attackby(obj/item/W as obj, mob/user as mob)
	if (istype(W, /obj/item/card/id)||istype(W, /obj/item/device/pda))
		if (src.allowed(user) && !open && !emagged)
			src.locked = !src.locked
			to_chat(user, "<span class='notice'>Controls are now [src.locked ? "locked." : "unlocked."]</span>")
			src.updateUsrDialog()
		else
			if(emagged)
				to_chat(user, "<span class='warning'>ERROR</span>")
			if(open)
				to_chat(user, "<span class='warning'>Please close the access panel before locking it.</span>")
			else
				to_chat(user, "<span class='warning'>Access denied.</span>")

	else if (istype(W, /obj/item/reagent_container/glass))
		if(src.locked)
			to_chat(user, "<span class='notice'>You cannot insert a beaker because the panel is locked.</span>")
			return
		if(!isnull(src.reagent_glass))
			to_chat(user, "<span class='notice'>There is already a beaker loaded.</span>")
			return

		if(user.transferItemToLoc(W, src))
			reagent_glass = W
			to_chat(user, "<span class='notice'>You insert [W].</span>")
			src.updateUsrDialog()
		return

	else
		..()
		if (health < maxhealth && !isscrewdriver(W) && W.force)
			step_to(src, (get_step_away(src,user)))

/obj/machinery/bot/medbot/Emag(mob/user as mob)
	..()
	if(open && !locked)
		if(user) to_chat(user, "<span class='warning'>You short out [src]'s reagent synthesis circuits.</span>")
		spawn(0)
			for(var/mob/O in hearers(src, null))
				O.show_message("<span class='danger'>[src] buzzes oddly!</span>", 1)
		flick("medibot_spark", src)
		src.patient = null
		if(user) src.oldpatient = user
		src.currently_healing = 0
		src.last_found = world.time
		src.anchored = 0
		src.emagged = 2
		src.safety_checks = 0
		src.on = 1
		src.icon_state = "medibot[src.on]"

/obj/machinery/bot/medbot/process()
	set background = 1

	if(!src.on)
		src.stunned = 0
		return

	if(src.stunned)
		src.icon_state = "medibota"
		src.stunned--

		src.oldpatient = src.patient
		src.patient = null
		src.currently_healing = 0

		if(src.stunned <= 0)
			src.icon_state = "medibot[src.on]"
			src.stunned = 0
		return

	if(src.frustration > 8)
		src.nextPatient()
		src.path = new()

	if(!src.patient)
		if(!src.shut_up && prob(1))
			var/message = pick("Radar, put a mask on!","There's always a catch, and it's the best there is.","I knew it, I should've been a plastic surgeon.","What kind of medbay is this? Everyone's dropping like dead flies.","Delicious!")
			src.speak(message)

		for (var/mob/living/carbon/C in view(7,src)) //Time to find a patient!
			if ((C.stat == 2) || !ishuman(C))
				continue

			if ((C == src.oldpatient) && (world.time < src.last_found + 100))
				continue

			if(src.assess_patient(C))
				src.patient = C
				src.oldpatient = C
				src.last_found = world.time
				if((src.last_newpatient_speak + 300) < world.time) //Don't spam these messages!
					var/message = pick("Hey, [C.name]! Hold on, I'm coming.","Wait [C.name]! I want to help!","[C.name], you appear to be injured!")
					src.speak(message)
					src.visible_message("<b>[src]</b> points at [C.name]!")
					src.last_newpatient_speak = world.time
					//if(declare_treatment)
					//	var/area/location = get_area(src)
					//	broadcast_medical_hud_message("[src.name] is treating <b>[C]</b> in <b>[location]</b>", src)
				break
			else
				continue


	if(src.patient && Adjacent(patient))
		if(!src.currently_healing)
			src.currently_healing = 1
			src.frustration = 0
			src.medicate_patient(src.patient)
		return

	else if(src.patient && (src.path.len) && (get_dist(src.patient,src.path[src.path.len]) > 2))
		src.path = new()
		src.currently_healing = 0
		src.last_found = world.time

	if(src.patient && src.path.len == 0 && (get_dist(src,src.patient) > 1))
		spawn(0)
			src.path = AStar(src.loc, get_turf(src.patient), /turf/proc/CardinalTurfsWithAccess, /turf/proc/Distance, 0, 30,id=botcard)
			if (!path) path = list()
			if(src.path.len == 0)
				src.oldpatient = src.patient
				src.patient = null
				src.currently_healing = 0
				src.last_found = world.time
		return

	if(src.path.len > 0 && src.patient)
		step_to(src, src.path[1])
		src.path -= src.path[1]
		spawn(3)
			if(src.path.len)
				step_to(src, src.path[1])
				src.path -= src.path[1]

	if(src.path.len > 8 && src.patient)
		src.frustration++

	return


/*
 *   Decide if the current patient needs medical attention
 */ 
/obj/machinery/bot/medbot/proc/assess_patient(mob/living/carbon/C as mob)
	
	// welp too late for them!
	if(C.stat == 2)
		return 0 

	// Kevorkian school of robotic medical assistants.
	if(C.suiciding)
		return 0 

	// Everyone needs our medicine. (Our medicine is toxins)
	if(emagged == 2) 
		return 1

	// Assign values into damagetype array
	// Virus code is taken from original medibot  
	// Can't loop this because whoever wrote the damage codebase 
	// put them all in separate functions instead of 
	// C.getDamageOfType("brute")
	for (var/damagetype in damagetypes) 
		patient_damagetypes[damagetype] = 0
	patient_damagetypes["brute"] = C.getBruteLoss()
	patient_damagetypes["burn"] = C.getBurnLoss()
	patient_damagetypes["oxy"] = C.getOxyLoss()
	patient_damagetypes["tox"] = C.getToxLoss()
	for(var/datum/disease/D in C.viruses)
		if((D.stage > 1) || (D.spread_type == AIRBORNE))
			patient_damagetypes["virus"] = 1;

	// If any damagetype >= 20, administer medication
	for (var/damageAmount in patient_damagetypes)
		if (damageAmount >= heal_threshold)
			return 1
	
	// Special case for virus infection
	if (patient_damagetypes["virus"])
		return 1

	return 0

/*
 *  Medicate the patient
 *  This proc gets called AFTER we've decided on treatment 
 */
/obj/machinery/bot/medbot/proc/medicate_patient(mob/living/carbon/C as mob)
	
	// Hello? Is this thing on?
	if(!src.on)
		return

	// Ignore nonbiologicals 
	if(!istype(C))
		src.nextPatient()
		return

	// Ignore dead patients
	if(C.stat == 2)
		src.speak(pick("No! NO!","Live, damnit! LIVE!","I...I've never lost a patient before. Not today, I mean."))
		src.nextPatient()
		return

	var/reagentToInject = null
	var/amountToInject = null
	var/beakerContentsValid = 0

	// Treatment: loop through each damagetype and decide on treatment 
	for (var/damagetype in damagetypes)
		if ((patient_damagetypes[damagetype] >= heal_threshold)||(damagetype == "virus" && patient_damagetypes[damagetype]))
			// Subroutine that checks if patient has already been treated 
			for (var/medicine in medicine_directory[damagetype])
				if (C.reagent_list.Find(medicine))
					break
					break 

			// Get med (this includes choosing the correct med in the beaker)
			for (var/medicine in medicine_directory[damagetype])

				// Here's the main bit: check if we have sufficient beaker contents 
				// If we have ANY of a med, draw from internal container 
				if (use_beaker && reagent_glass && reagents_glass.reagents.total_volume && src.reagent_glass.reagents.has_reagent(medicine))
					reagentToInject = medicine
					beakerContentsValid = 1
					break
					
					// Fallback medicine types. If we hit these we can break because we 
					// know we're gonna use our internal synthesizer, AKA space magic 
				else if (medicine == "tricordrazine")
					reagentToInject = medicine
					break
				else if (medicine == "spaceacillin")
					reagentToInject = medicine
					break

			// Set our injection amounts
			// Special snowflake code for dex+
			if (reagentToInject != "dexalinplus")
				amountToInject = injection_amount
			else 
				amountToInject = 5

			// OD check 
			if (isInjectionSafe(C, reagentToInject, amountToInject))
				
				// Unconditionally inject toxin
				if (emagged == 2)
					beakerContentsValid = 0
					amountToInject = 15
					reagentToInject = "toxin"

				src.icon_state = "medibots"
					visible_message("<span class='danger'>[src] is trying to inject [src.patient]!</span>")
					spawn(30)
						
						if ((get_dist(src, patient) <= 1) && (on))
							// Use our beaker if we can 
							if(beakerContentsValid)
								reagent_glass.reagents.trans_id_to(patient, reagentToInject, amountToInject)
								reagent_glass.reagents.reaction(patient, 2)
							
							// "Internal synthesizers"
							else if (can_synthesize.Find(reagentToInject))
								patient.reagents.add_reagent(reagentToAdd, amountToInject)
							
							visible_message("<span class='danger'>[src] injects [src.patient] with the syringe!</span>")

			src.icon_state = "medibot[src.on]"
			src.currently_healing = 0
		
			// Cleanups 
			ASSERT(amountToInject)
			ASSERT(reagentToInject)
			reagentToInject = null
			amountToInject = null
			beakerContentsValid = 0

	// Chirp to let the patient know they're good to go
	src.speak("All patched up!")
	src.speak(pick("An apple a day keeps me away.","Feel better soon!"))
	src.nextPatient()
	return
	


/obj/machinery/bot/medbot/proc/speak(var/message)
	if((!src.on) || (!message))
		return
	visible_message("[src] beeps, \"[message]\"")
	return

/obj/machinery/bot/medbot/explode()
	src.on = 0
	visible_message("<span class='danger'>[src] blows apart!</span>", 1)
	var/turf/Tsec = get_turf(src)

	new /obj/item/storage/firstaid(Tsec)

	new /obj/item/device/assembly/prox_sensor(Tsec)

	new /obj/item/device/healthanalyzer(Tsec)

	if(src.reagent_glass)
		src.reagent_glass.loc = Tsec
		src.reagent_glass = null

	if (prob(50))
		new /obj/item/robot_parts/l_arm(Tsec)

	var/datum/effect_system/spark_spread/s = new /datum/effect_system/spark_spread
	s.set_up(3, 1, src)
	s.start()
	qdel(src)
	return

/obj/machinery/bot/medbot/Bump(M as mob|obj) //Leave no door unopened!
	if ((istype(M, /obj/machinery/door)) && (!isnull(src.botcard)))
		var/obj/machinery/door/D = M
		if (!istype(D, /obj/machinery/door/firedoor) && D.check_access(src.botcard) && !istype(D,/obj/machinery/door/poddoor))
			D.open()
			src.frustration = 0
	else if ((istype(M, /mob/living/)) && (!src.anchored))
		src.loc = M:loc
		src.frustration = 0
	return

 
//  Check if the given patient will be OD'd if the given drug is administered.
//  To use the bot's default injection amount, pass in NULL, otherwise will 
//  be calculated using the passed value. -4/4/2019 
/obj/machinery/bot/medbot/isInjectionSafe(mob/living/Carbon/C, var/reagent, var/injectAmnt)

	// If we're not checking for safety, unconditionally return true 
 	if (!src.safety_checks)
		return 1
 	
 	// If total resultant drugs >= OD volume, return false 
 	return

/*
 *  Helper proc for a lot of boilerplate 
 */
/obj/machinery/bot/medbot/nextPatient()
	src.oldpatient = src.patient
	src.patient = null
	src.currently_healing = 0
	src.last_found = world.time
	return

/*
 *	Medbot Assembly -- Can be made out of all three medkits.
 */
/obj/item/storage/firstaid/attackby(var/obj/item/robot_parts/S, mob/user as mob)

	if ((!istype(S, /obj/item/robot_parts/l_arm)) && (!istype(S, /obj/item/robot_parts/r_arm)))
		..()
		return

	//Making a medibot!
	if(src.contents.len >= 1)
		to_chat(user, "<span class='notice'>You need to empty [src] out first.</span>")
		return

	var/obj/item/frame/firstaid_arm_assembly/A = new /obj/item/frame/firstaid_arm_assembly
	if(istype(src,/obj/item/storage/firstaid/fire))
		A.skin = "ointment"
	else if(istype(src,/obj/item/storage/firstaid/toxin))
		A.skin = "tox"
	else if(istype(src,/obj/item/storage/firstaid/o2))
		A.skin = "o2"

	qdel(S)
	user.put_in_hands(A)
	to_chat(user, "<span class='notice'>You add the robot arm to the first aid kit.</span>")
	user.temporarilyRemoveItemFromInventory(src)
	qdel(src)
