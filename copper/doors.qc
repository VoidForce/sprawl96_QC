
/*
=============================================================================
Doors are similar to buttons, but can spawn a fat trigger field around them
to open without a touch, and they link together to form simultaneous
double/quad doors.
 
Door.owner is the master door.  If there is only one door, it points to itself.
If multiple doors, all will point to a single one.

Door.enemy chains from the master door through all doors linked in the chain.
=============================================================================
*/

float DOOR_START_OPEN = 1;
float DOOR_SPECIAL = 2;
float DOOR_DONT_LINK = 4;
float DOOR_GOLD_KEY = 8;
float DOOR_SILVER_KEY = 16;
float DOOR_TOGGLE = 32;
float DOOR_CRUSHER = 64;

/*
=============================================================================

THINK FUNCTIONS

=============================================================================
*/

void() door_blocked =
{
	T_Damage (other, self, self, self.dmg, NOFLAGS);
	
	// if a door has a negative wait, it would never come back if blocked,
	// so let it just squash the object to death real fast
	if (self.wait >= 0 && !(self.spawnflags & DOOR_CRUSHER))
	{
		if (self.state == STATE_DOWN)
			door_go_up ();
		else
			door_go_down ();
	}
}


void() door_hit_top =
{
	sound (self, CHAN_VOICE, self.noise1, 1, ATTN_NORM);
	self.state = STATE_TOP;
	SUB_UseTargetsAlt(target2);
	if (self.spawnflags & DOOR_TOGGLE)
		return;		// don't come down automatically
	self.think = door_go_down;
	self.nextthink = self.ltime + self.wait;
	
}

void() door_hit_bottom =
{
	sound (self, CHAN_VOICE, self.noise1, 1, ATTN_NORM);
	self.frame = self.skin;
	self.state = STATE_BOTTOM;
	
	SUB_UseTargetsAlt(target4);
}

void() door_go_down =
{
	//dprint("door_go_down\n");
	sound (self, CHAN_VOICE, self.noise2, 1, ATTN_NORM);
	if (self.max_health)
	{
		self.takedamage = DAMAGE_YES;
		self.health = self.max_health;
	}
	
	self.state = STATE_DOWN;
	SUB_CalcMove (self.pos1, self.speed2, door_hit_bottom);
	
	SUB_UseTargetsAlt(target3);
}

void() door_go_up =
{
	//dprint("door_go_up\n");
	if (self.state == STATE_UP)
		return;		// already going up

	if (self.state == STATE_TOP)
	{	// reset top wait time
		if (self.spawnflags & DOOR_TOGGLE)
			return;		// don't come down automatically
		self.nextthink = self.ltime + self.wait;
		return;
	}
	
	sound (self, CHAN_VOICE, self.noise2, 1, ATTN_NORM);
	self.state = STATE_UP;
	SUB_CalcMove (self.pos2, self.speed, door_hit_top);
	self.frame = !self.skin;

	if (!SUB_UseTargetsAlt(target))
		SUB_UseTargetsSilent();	// door messages are for when they *don't* open
}

/*
=============================================================================

ACTIVATION FUNCTIONS

=============================================================================
*/

void() door_fire =
{
	local entity 	oself;
	local entity	starte;
		
	//dprint("door_fire\n");
	if (self.owner != self)
		objerror ("door_fire: self.owner != self");

	// play use key sound
	if (self.items)
		sound (self, CHAN_BODY, self.noise4, 1, ATTN_NORM);	// was chan_voice, door move sound was cutting it off

	if (!( self.spawnflags & DOOR_TOGGLE ) ) 
	{
		self.message = string_null;		// no more message
	}
	else
	{
		oself = self;
		if (self.state == STATE_TOP || self.state == STATE_UP )
		{
			starte = self;
			do {
				if (self.classname == "shadowmonitor")
					door_shadowmonitor_go();
				else
					door_go_down ();
				self = self.enemy;
			} while ( (self != starte) && (self != world) );
			self = oself;
			return;
		}
	}

	// trigger all paired doors
	starte = self;
	if ( !( self.spawnflags & DOOR_TOGGLE ) || ( self.spawnflags & DOOR_TOGGLE && self.state == STATE_BOTTOM) )
	do {
		if (self.classname == "shadowmonitor")
			door_shadowmonitor_go();
		else
			door_go_up ();
		self = self.enemy;
	} while ( (self != starte) && (self != world) );
	self = oself;
}


void() door_use =
{
	//dprint("door_use\n");
	if (self.copperflags & CFL_LOCKED) return;
	if (!( self.spawnflags & DOOR_TOGGLE ) ) 
	{
		self.message = string_null;			// door message are for touch only
		self.owner.message = string_null;	
		self.enemy.message = string_null;
	}
	self.takedamage = DAMAGE_NO;	// wil be reset upon return
	SUB_CallAsSelf(door_fire,self.owner);
}

void() door_trigger_touch =
{
	if (other.health <= 0) return;
	if (other.movetype == MOVETYPE_NOCLIP) return;
	if (time < self.attack_finished) return;
		
	// silly fix for sleeping monsters standing behind doors inside their touch fields causing them to open
	if (other.flags & FL_MONSTER && other.enemy == world && other.goalentity == world) return;
	
	self.attack_finished = time + 1;
	activator = other;
	self = self.owner;
	door_use ();
}

void() door_killed =
{
	local entity oself;
	
	oself = self;
	self = self.owner;
	self.health = self.max_health;
	door_use ();
	self = oself;
}

void(entity d) door_force =
{
	entity od;
	od = d.owner;
	do {
		od.items = 0;
		od = od.enemy;
	} while (od != d);

	SUB_CallAsSelf(door_fire,d.owner);
}

/*
================
door_touch

Prints messages and opens key doors
================
*/
void() door_touch =
{
	if (!CheckValidTouch()) return;

	self = self.owner;
	if (self.attack_finished > time)
		return;

	self.attack_finished = time + 1;

	if (self.message != string_null && self.state == STATE_BOTTOM && !(self.items))
	{
		centerprint (other, self.message);
		sound (other, CHAN_VOICE, self.noise3, 1, ATTN_NORM);
	}
	
	// from here on is key door stuff
	if (!self.items)
		return;
	// key doors don't spawn trigger fields, so door_touch does a lot of what door_trigger_touch does

	if ( (self.items & other.items) != self.items || self.copperflags & CFL_LOCKED )
	{
		centerprint (other, self.owner.message);
		sound (self, CHAN_VOICE, self.noise3, 1, ATTN_NORM);
		return;
	}
	
	if (self.items & IT_KEY1)
	{
		key_take_silver(other);
	}
	else if (self.items & IT_KEY2)
	{
		key_take_gold(other);
	}
	else
	{
		other.items = other.items - self.items;
	}
	
	self.touch = SUB_Null;
	entity t = self.enemy;
	while (t != self)// get paired doors
	{
		t.touch = SUB_Null;
		t = t.enemy;
	}
		
	activator = other;
	
	door_use ();
}

void(float unlock) door_lock =
{
	entity c;
	
	//dprint("door_lock\n");
	if (unlock) door_unlock_do(self);
	else door_lock_do(self);
	// inner loop checks for doors that are linked by touch and not targetname
	c = self.enemy;
	do {
		if (c.targetname != self.targetname)	// outer loop will find this one
			if (unlock) door_unlock_do(c);
			else door_lock_do(c);
		c = c.enemy;
	} while (c != self);
}

void(entity d) door_lock_do =
{
	//dprint("door_lock_do\n");
	entity e;
	if (d.copperflags & CFL_LOCKED)
		return;
	d.copperflags = d.copperflags | CFL_LOCKED;

	// close any open doors immediately
	if (d.state != STATE_BOTTOM && !(d.spawnflags & DOOR_TOGGLE || d.wait == -1))
	{
		e = d;
		do {
			SUB_CallAsSelf(door_go_down,e);
			e = e.enemy;
		}
		while ( e != d && e != world );
	}
	
	if (d.max_health)
	{
		d.takedamage = DAMAGE_NO;
	}
	else
	{
		/*if (d.owner.trigger_field == world && !d.owner.items && !(d.spawnflags & DOOR_TOGGLE))
			objerror("door being locked doesn't have a trigger");
		else*/ if (d.owner.trigger_field)
			d.owner.trigger_field.touch = SUB_Null;
	}
}

void(entity d) door_unlock_do =
{
	//dprint("door_unlock_do\n");
	if (!(d.copperflags & CFL_LOCKED))
		return;
		
	d.copperflags = not(d.copperflags, CFL_LOCKED);
	
	if (d.max_health)
	{
		d.takedamage = DAMAGE_YES;
		d.health = d.max_health;
	}
	else
	{
		/*if (d.owner.trigger_field == world && !d.owner.items && !(d.spawnflags & DOOR_TOGGLE))
			objerror("door being unlocked doesn't have a trigger");
		else*/ if (d.owner.trigger_field)
			d.owner.trigger_field.touch = door_trigger_touch;
	}
}

// checks if a door ONLY has locks targeting it
float(entity d) door_getslocked =
{
	if (d.targetname == string_null)
		return FALSE;
	
	entity t;
	float found = FALSE;
	t = find(world, target, d.targetname);
	while (t) {
		found = TRUE;
		if (t.classname != "target_lock") return FALSE;
		t = find(t, target, d.targetname);
	}
	t = find(world, target2, d.targetname);
	while (t) {
		found = TRUE;
		if (t.classname != "target_lock") return FALSE;
		t = find(t, target2, d.targetname);
	}
	t = find(world, target3, d.targetname);
	while (t) {
		found = TRUE;
		if (t.classname != "target_lock") return FALSE;
		t = find(t, target3, d.targetname);
	}
	t = find(world, target4, d.targetname);
	while (t) {
		found = TRUE;
		if (t.classname != "target_lock") return FALSE;
		t = find(t, target4, d.targetname);
	}
	return found;	// no targeters has to be FALSE
}

/*
=============================================================================

SWITCHABLE SHADOWS

I do not want to screw around with SUB_CalcMove or bog doors down even further with
thinking-while-moving, so doors with switchable shadows will spawn a little helper
monitor to do that to keep mover code clean

=============================================================================
*/

void() door_shadowmonitor_go =
{
	float frac;
	entity o = self.owner;
	if (o.state == STATE_TOP)	// at pos2 (open)
		frac = 0;
	else if (o.state == STATE_BOTTOM)	// at pos1 (closed)
		frac = 1;
	else
		frac = vlen(o.origin - o.pos2) / vlen(o.pos2 - o.pos1);	// distance FROM pos2

	// 1 blocks light, 0 admits light
	bmodel_lightstyle(o, frac);
	
	// pay attention to owner state so we stop thinking when the door is done moving
	if ((o.state == STATE_TOP) && (o.spawnflags & DOOR_TOGGLE) || o.state == STATE_BOTTOM)
		return;

	if (o.state == STATE_TOP)
		self.nextthink = time + (o.nextthink - o.ltime);
	else
		self.nextthink = time + min(0.05, (o.nextthink - o.ltime));
		
	self.think = door_shadowmonitor_go;
}

void(entity d) door_shadowmonitor =
{
	entity m = spawn();
	m.classname = "shadowmonitor";
	m.owner = d;
	m.enemy = d.enemy;
	d.enemy = m;

	if (d.style < 0)
	{
		d.style *= -1;
		d.copperflags |= CFL_INVLIGHT;
	}
	if (d.spawnflags & DOOR_START_OPEN)
	{
		if (d.copperflags & CFL_INVLIGHT)
			d.copperflags -= CFL_INVLIGHT;
		else
			d.copperflags |= CFL_INVLIGHT;
	}
	
	bmodel_lightstyle(d, 1);
}

/*
=============================================================================

SPAWNING FUNCTIONS

=============================================================================
*/

entity(vector fmins, vector fmaxs) door_spawn_field =
{
	local entity	trigger;
	local	vector	t1, t2;
	//dprint("spawning door field\n");
	trigger = spawn();
	trigger.movetype = MOVETYPE_NONE;
	trigger.solid = SOLID_TRIGGER;
	trigger.owner = self;
	trigger.touch = door_trigger_touch;

	t1 = fmins;
	t2 = fmaxs;
	setsize (trigger, t1 - '60 60 8', t2 + '60 60 8');
	return (trigger);
}

void(vector cmins, vector cmaxs) door_finalize =
{
	entity t;
	// switch positions after linking so START_OPEN doors link properly
	t = self;
	do {
		// DOOR_START_OPEN is to allow an entity to be lighted in the closed position
		// but spawn in the open position
		if (t.spawnflags & DOOR_START_OPEN)
		{
			setorigin (t, t.pos2);
			t.pos2 = t.pos1;
			t.pos1 = t.origin;
		}
		t = t.enemy;
	} while (t != self);
			
	if (self.items)
	{
		door_key_init();
		return;
	}

	t = self;
	do {
		// put a light fade monitor in the enemy chain
		if (self.style || self.switchshadstyle)
		{
			door_shadowmonitor(t);
			break;
		}
		t = t.enemy;
	} while (t != self);

	if (self.health)
		return;
	if (self.targetname != string_null)
		if (!door_getslocked(self) || self.spawnflags & DOOR_TOGGLE)
			return;
	
	self.trigger_field = door_spawn_field(cmins, cmaxs);
	
	if (self.copperflags & CFL_LOCKED)
		door_lock(FALSE);
}

float(entity door, entity master) door_can_link =
{
	if (door == master) return TRUE;	// first door
	if (door.enemy) return FALSE;	// already linked
	if (door.spawnflags & DOOR_DONT_LINK) return FALSE;	// will finalize itself later

	if (door.targetname != string_null && master.targetname != string_null && master.targetname != door.targetname)
		return FALSE;	// part of different systems, might only touch coincidentally
	
	if (door.items && master.items && !(master.items & door.items))
		return FALSE;	// different items requirements
	
	return TRUE;
}

/*
=============
door_link
=============
*/
void() door_link =
{
	entity	t, masterdoor;
	vector	cmins, cmaxs;

	if (self.enemy)
		return;		// already linked by another door
	if (self.spawnflags & DOOR_DONT_LINK)
	{
		self.owner = self.enemy = self;
		door_finalize(self.mins, self.maxs);
		return;		// don't want to link this door
	}

	cmins = self.mins;
	cmaxs = self.maxs;
	
	masterdoor = self;
	t = self;
	
	do
	{
		self.owner = masterdoor;
		
		if (self != masterdoor)
		{
			if ((self.targetname != string_null && masterdoor.targetname == string_null) ||
				self.targetname == masterdoor.targetname)
			{
				// all the doors in the chain having the same targetname will cause
				// the whole chain to be triggered once for every door in the chain
				masterdoor.targetname = self.targetname;
				self.targetname = string_null;
			}
			masterdoor.items |= self.items;
			if (self.health != 0 && masterdoor.health == 0)
				masterdoor.health = self.health;

			SUB_MergeTargets(masterdoor);
			self.target = string_null;
			self.target2 = string_null;
			self.target3 = string_null;
			self.target4 = string_null;
			self.killtarget = string_null;
			if (self.message != string_null && masterdoor.message == string_null)
				masterdoor.message = self.message;
		}

		// skip doors with other targetnames to not fold them into the loop
		do {
			t = find (t, classname, self.classname);	
		} while (t && (!door_can_link(t,masterdoor) || !EntitiesTouching(self,t)));
		
		if (!t)
		{
			self.enemy = masterdoor;		// make the chain a loop
			self = self.owner;

			door_finalize(cmins, cmaxs);
			
			return;
		}

		self.enemy = t;
		self = t;

		cmins_x = min(t.mins_x, cmins_x);
		cmins_y = min(t.mins_y, cmins_y);
		cmins_z = min(t.mins_z, cmins_z);
		cmaxs_x = max(t.maxs_x, cmaxs_x);
		cmaxs_y = max(t.maxs_y, cmaxs_y);
		cmaxs_z = max(t.maxs_z, cmaxs_z);
	} while (t);
}

void() LinkDoors = {door_link();}

void() door_key_init =
{
	if (self.message == string_null)
	{
		if (self.items & IT_KEY1)
		{
			if (world.worldtype == 2)
				self.message = "You need the Silver Keycard";
			else if (world.worldtype == 1)
				self.message = "You need the Silver Runekey";
			else if (world.worldtype == 0)
				self.message = "You need the Silver Key";
		}
		else if (self.items & IT_KEY2)
		{
			if (world.worldtype == 2)
				self.message = "You need the Gold Keycard";
			else if (world.worldtype == 1)
				self.message = "You need the Gold Runekey";			
			else if (world.worldtype == 0)
				self.message = "You need the Gold Key";
		}
	}
	if (self.items)
	{
		entity t = self;
		do {
			t.wait = -1;
			t = t.enemy;
		} while (t != self);
	}
}

// always let specific noise fields on a door override 'sounds' regardless
// of number - maps that use custom door sounds can use 'sounds 5' to skip
// the sound code as a hack, but the sounds menu is longer in copper
void(.string nois, string path) door_set_sound =
{
	if (self.nois == string_null) self.nois = path;
}

void() door_sounds_init =
{
	if (self.items & (IT_KEY1 | IT_KEY2))
	{
		if (world.worldtype == 1)
		{
			door_set_sound(noise3, "doors/runetry.wav");
			door_set_sound(noise4, "doors/runeuse.wav");
		}
		else if (world.worldtype == 2)
		{
			door_set_sound(noise3, "doors/basetry.wav");
			door_set_sound(noise4, "doors/baseuse.wav");
		}
		else
		{
			door_set_sound(noise3, "doors/medtry.wav");
			door_set_sound(noise4, "doors/meduse.wav");
		} 
	}
	else
	{
		if (world.worldtype == 2)
		{
			door_set_sound(noise3, "doors/locked5.wav");
		}
		else
		{
			door_set_sound(noise3, "doors/locked4.wav");
		} 
		door_set_sound(noise4, "misc/null.wav");
	}
	
	if (self.sounds == 0)
	{
		door_set_sound(noise1, "misc/null.wav");
		door_set_sound(noise2, "misc/null.wav");
	}
	else if (self.sounds == 1)
	{
		door_set_sound(noise1, "doors/drclos4.wav");
		door_set_sound(noise2, "doors/doormv1.wav");
	}
	else if (self.sounds == 2)
	{
		door_set_sound(noise1, "doors/hydro2.wav");
		door_set_sound(noise2, "doors/hydro1.wav");
	}
	else if (self.sounds == 3)
	{
		door_set_sound(noise1, "doors/stndr2.wav");
		door_set_sound(noise2, "doors/stndr1.wav");
	}
	else if (self.sounds == 4)
	{
		door_set_sound(noise1, "doors/ddoor2.wav");
		door_set_sound(noise2, "doors/ddoor1.wav");
	}
	else if (self.sounds == 5)
	{
		door_set_sound(noise1, "doors/drclos4.wav");
		door_set_sound(noise2, "doors/winch2.wav");
	}
	else if (self.sounds == 6)
	{
		door_set_sound(noise1, "doors/basesec2.wav");
		door_set_sound(noise2, "doors/basesec1.wav");
	}
	
	precache_sound_safe(self.noise1);
	precache_sound_safe(self.noise2);
	precache_sound_safe(self.noise3);
	precache_sound_safe(self.noise4);
	//precache_sound_safe("doors/locked4.wav");
}

/*QUAKED func_door (0 .5 .8) ? START_OPEN ? DONT_LINK GOLD_KEY SILVER_KEY TOGGLE CRUSHER
Door. Opens; closes. 
If two doors touch, they are assumed to be connected and operate as a unit. Targets, targetnames, and the Crusher and Toggle spawnflags are safely shared between linked doors automatically.
Doors will not link if either has the "dont_link" spawnflag, if they have different targetnames, or different key requirements.

SPAWNFLAGS
"start_open" causes the door to move to its destination when spawned, and operate in reverse. It is used to temporarily or permanently close off an area when triggered (not usefull for touch or takedamage doors).
"dont_link" don't link to any touching doors
"toggle" causes the door to wait in both the start and end states for a trigger event.
"crusher" do not reverse when blocked

Key doors are always wait -1.

"message"	is printed when the door is touched if it is a trigger door and it hasn't been fired yet.  if locked, will print this instead of default silver/gold message.
"angle"		determines the opening direction
"targetname" if set, no touch field will be spawned and a remote button or trigger activates the door, unless the door is only targeted by a target_lock.
"health"	if set, door must be shot open
"speed"		movement speed (100 default)
"speed2"	make close speed different from open speed
"wait"		wait before returning (3 default, -1 = never return)
"lip"		lip remaining at end of move (8 default)
"distance"	specify movement distance directly, overrides lip (-1 to explicitly not move)
"dmg"		damage to inflict when blocked (2 default)
"noise1-4"	override stop/open/locked/unlocked sounds, respectively
"sounds"
0) silent
1) stone
2) base
3) stone chain
4) hissy metal
5) winchy secret door
6) base secret door

Alt Target Pattern: 'target' when starting to open, 'target2' when opened, 'target3' when starting to close, 'target4' when closed.
*/
/*FGD
@SolidClass base(Angle, Appearflags, Targetname, Target, Func, FuncInvis, AltTarget) = func_door : 
"Door. Opens; closes. 
If two doors touch, they are assumed to be connected and operate as a unit. Targets, targetnames, and the Crusher and Toggle spawnflags are safely shared between linked doors automatically.
Doors will not link if either has the 'don't link' spawnflag, if they have different targetnames, or different key requirements.

Alt Target Pattern: 'target' when starting to open, 'target2' when opened, 'target3' when starting to close, 'target4' when closed." 
[
	speed(integer) : "Speed" : 100
	speed2(integer) : "Close Speed (if different from open speed)" : 0
	sounds(choices) : "Sound" : 0 = 
	[
        0: "Silent"
		1: "Stone"
		2: "Machine"
		3: "Stone Chain"
		4: "Screechy Metal"
		5: "Winchy secret door"
		6: "Base secret door"
	]
	noise1(string) : "Override stop sound"
	noise2(string) : "Override move sound"
	noise3(string) : "Override key-required sound"
	noise4(string) : "Override key-unlocked sound"
	wait(string) : "Wait before close" : "3" 
	lip(integer) : "Lip remaining at end of move" : 8
	distance(string) : "Distance to travel (overrides Lip)" : "0.0"
	dmg(integer) : "Damage inflicted when blocked" : 2
	message(string) : "Message printed when the door is touched if it is a trigger door and it hasn't been fired yet. If locked, will print this instead of default silver/gold message."
	health(integer) : "Health (shootable)" : 0
	targetname(target_source) : "Name. If set, no touch field will be spawned and a remote button or trigger must activates the door, UNLESS the door is only targeted by a target_lock."
	spawnflags(flags) =
	[
		1 : "Starts Open" : 0
		4 : "Don't link with touching" : 0
		8 : "Gold Key" : 0
        16 : "Silver Key" : 0
        32 : "Toggle" : 0
        64 : "Crusher" : 0
	]
]
*/
void() func_door =
{
	if (!SUB_ShouldSpawn()) return;
	self.sprawlflags |= SFL_MOVINGSOLID;
	
	SetMovedir ();

	self.max_health = self.health;
	//self.classname = "door";

	if (!self.speed)
		self.speed = 100;
	if (!self.speed2)
		self.speed2 = self.speed;
	self.dmg = zeroconvertdefault(self.dmg, 2);
	if (!self.lip)
		self.lip = 8;
	if (self.spawnflags & DOOR_SILVER_KEY)
	{
		self.items = IT_KEY1;
		self.wait = -1;
	}
	else if (self.spawnflags & DOOR_GOLD_KEY)
	{
		self.items = IT_KEY2;
		self.wait = -1;
	}
	door_sounds_init();

	//door_key_init();
	
	if (!self.wait)
		self.wait = 3;
	
	if (self.spawnflags & 128)
		self.use = func_door_spawn;
	else
		func_door_spawn();
}

void() func_door_spawn =
{
	self.solid = SOLID_BSP;
	self.movetype = MOVETYPE_PUSH;
	setorigin (self, self.origin);	
	setmodel (self, self.model);

	self.distance = zeroconvertdefault(self.distance, 
		BoundsAngleSize( self.movedir, self.size ) - self.lip);
		// ^^ janky for non-cardinal angles
		
	if (self.pos1 && self.pos2)
	{
		setorigin(self, self.pos1);
	}
	else
	{
		self.pos1 = self.origin;
		self.pos2 = self.pos1 + self.movedir * self.distance;
	}

	self.state = STATE_BOTTOM;

	if (self.health)
	{
		self.takedamage = DAMAGE_YES;
		self.th_die = door_killed;
	}
	
	self.blocked = door_blocked;
	self.use = door_use;
	self.touch = door_touch;
	self.lock = door_lock;

	// door_link can't be done until all of the doors have been spawned, so
	// the sizes can be detected properly.
	self.think = door_link;
	self.nextthink = self.ltime + 0.1;
}

/*
=============================================================================

SECRET DOORS

=============================================================================
*/

void() secretdoor_move1;
void() secretdoor_move2;
void() secretdoor_move3;
void() secretdoor_move4;
void() secretdoor_move5;
void() secretdoor_move6;
void() secretdoor_done;

float SECRET_OPEN_ONCE = 1;		// stays open
float SECRET_1ST_LEFT = 2;		// 1st move is left of angle
float SECRET_1ST_DOWN = 4;		// 1st move is down from angle
float SECRET_NO_SHOOT = 8;		// only opened by trigger
float SECRET_YES_SHOOT = 16;	// shootable even if targeted

void () secretdoor_use =
{
	self.health = self.max_health;

	// enter correct phase of opening if retriggered while moving
	if (self.origin != self.oldorigin)
	{
		secret_door_force(self);
		return;
	}
	
	self.message = string_null;		// no more message

	SUB_UseTargetsSilent();				// fire all targets / killtargets
	
	if (!(self.spawnflags & SECRET_NO_SHOOT))
	{
		// self.th_pain = SUB_Null;
		self.takedamage = DAMAGE_NO;
	}
	self.velocity = '0 0 0';

	secretdoor_move0();
}

// hodor correctly depending on what state the door is in
void(entity door) secret_door_force =
{
	entity oself;
	oself = self;
	self = door;
	if (self.think == secretdoor_move4)	// waiting in open pos, extend timer
	{
		self.nextthink = self.ltime + self.wait;
	}
	else if (self.think1 == secretdoor_move5)	// 2nd reverse move in progress or done
	{
		secretdoor_move2();	// restart 2nd open move
	}
	else if (self.think == secretdoor_move6 || self.origin == self.oldorigin)	// 1st reverse move in progress or done
	{
		secretdoor_move0();	// restart 1st open move
	}
	self = oself;
}

void(entity attacker, float damage) secretdoor_pain =
{
	if (attacker.classname != "player") return;	// no monsters opening secrets for you
	
	secretdoor_use();
}


void() secret_shadowmonitor_go =
{
	float opac, done;
	vector mv, p;
	entity o = self.owner;
	
	self.nextthink = time + min(0.05, (o.nextthink - o.ltime));
	
	if (o.think == secretdoor_move2 || o.think == secretdoor_move6)
	{
		opac = 1;
		done = TRUE;
	}
	else if (o.think == SUB_Null)
	{
		opac = 0;
		if (o.wait == -1)
			done = TRUE;
	}
	else if (o.think == secretdoor_move4)
	{
		opac = 0;
		self.nextthink += o.wait;
	}
	else
	{
		mv = o.dest2 - o.dest1;
		p = o.origin - o.dest2;
		opac = vlen(p) / vlen(mv);
	}

	bmodel_lightstyle(o, opac);

	if (done)
	{
		remove(self);
		return;
	}
	
	self.think = secret_shadowmonitor_go;
}


// Make a sound, wait a little...
void () secretdoor_move0 = 
{
	if (self.noise1 != string_null)
		sound(self, CHAN_VOICE, self.noise1, 1, ATTN_NORM);
	self.nextthink = self.ltime + 0.1;

	SUB_CalcMove(self.dest1, self.speed, secretdoor_move1);
	if (self.noise2 != string_null)
		sound(self, CHAN_VOICE, self.noise2, 1, ATTN_NORM);
}

// Wait after first movement...
void () secretdoor_move1 = 
{
	self.nextthink = self.ltime + 1.0;
	self.think = secretdoor_move2;
	if (self.noise3 != string_null)
		sound(self, CHAN_VOICE, self.noise3, 1, ATTN_NORM);
}

// Start moving sideways w/sound...
void () secretdoor_move2 =
{
	if (self.noise2 != string_null)
		sound(self, CHAN_VOICE, self.noise2, 1, ATTN_NORM);
	SUB_CalcMove(self.dest2, self.speed2, secretdoor_move3);
	
	if (!self.switchshadstyle && !self.style)
		return;
		
	entity shadow = spawn();
	shadow.classname = "shadowmonitor";
	shadow.owner = self;
	SUB_CallAsSelf(secret_shadowmonitor_go, shadow);
}

// Wait here until time to go back...
void () secretdoor_move3 =
{
	if (self.noise3 != string_null)
		sound(self, CHAN_VOICE, self.noise3, 1, ATTN_NORM);
	if (!(self.spawnflags & SECRET_OPEN_ONCE) || self.wait > 0)
	{
		self.nextthink = self.ltime + self.wait;
		self.think = secretdoor_move4;
		return;
	}
	self.think = SUB_Null;
}

// Move backward...
void () secretdoor_move4 =
{
	if (self.noise2 != string_null)
		sound(self, CHAN_VOICE, self.noise2, 1, ATTN_NORM);
	SUB_CalcMove(self.dest1, self.speed2, secretdoor_move5);		
}

// Wait 1 second...
void () secretdoor_move5 = 
{
	self.nextthink = self.ltime + 1.0;
	self.think = secretdoor_move6;
	if (self.noise3 != string_null)
		sound(self, CHAN_VOICE, self.noise3, 1, ATTN_NORM);
}

// last move ...
void () secretdoor_move6 =
{
	if (self.noise2 != string_null)
		sound(self, CHAN_VOICE, self.noise2, 1, ATTN_NORM);
	SUB_CalcMove(self.oldorigin, self.speed, secretdoor_done);
}

void () secretdoor_done =
{
	self.think1 = SUB_Null;
	if (!self.targetname || self.spawnflags & SECRET_YES_SHOOT)
	{
		self.health = self.max_health;
		self.takedamage = DAMAGE_YES;
		self.th_pain = secretdoor_pain;	
	}
	if (self.noise3 != string_null)
		sound(self, CHAN_VOICE, self.noise3, 1, ATTN_NORM);
}

void () secret_blocked =
{
	if (time < self.attack_finished)
		return;
	self.attack_finished = time + 0.5;
	T_Damage (other, self, self, self.dmg, NOFLAGS);
}

/*
================
secret_touch

Prints messages
================
*/
void() secret_touch =
{
	if (!CheckValidTouch()) return;

	if (self.attack_finished > time)
		return;

	self.attack_finished = time + 2;
	
	if (self.message != string_null)
	{
		centerprint (other, self.message);
		sound (other, CHAN_BODY, self.noise4, 1, ATTN_NORM);
	}
}

void() secret_door_moves =
{
	vector firstmove, secondmove;
	
	if (!self.dest1 && !self.dest2)
	{
		// dumb old way
		makevectors(self.mangle);
		if (self.spawnflags & SECRET_1ST_LEFT)
			firstmove = v_right * -1;
		else if (self.spawnflags & SECRET_1ST_DOWN) 
			firstmove = v_up * -1;
		else
			firstmove = v_right;
		secondmove = v_forward;
	}
	else
	{
		firstmove = normalize(self.dest1);
		secondmove = normalize(self.dest2);
	}
	
	if (!self.t_width)
		self.t_width = BoundsAngleSize(firstmove, self.size);
		
	if (!self.t_length)
		self.t_length = BoundsAngleSize(secondmove, self.size);

	self.dest1 = self.origin + firstmove * self.t_width;
	self.dest2 = self.dest1 + secondmove * self.t_length;
}

void() secret_door_find =
{
	// ok nobody knows what vectors are? what is our children learning
	entity p = find(world, targetname, self.target);

	// now we support literal pathcorners like a literal train
	if (p && p.classname == "path_corner" && p.target != string_null)
	{
		entity p2 = find(world, targetname, p.target);
		if (p2 && p2.classname == "path_corner")
		{
			self.dest1 = p.origin - self.mins;
			self.dest2 = p2.origin - self.mins;
			
			return;
		}
	}

	secret_door_moves();
}

/*QUAKED func_door_secret (0 .5 .8) ? OPEN_ONCE 1ST_LEFT 1ST_DOWN NO_SHOOT ALWAYS_SHOOT
Secret door. Slides back, then to the side. 

There are three ways to configure how this door moves:
1) Set 'Angle'. The secret door will first move to the right of that angle by t_width units, then in the direction of that angle by t_length units. The first move can be altered with the 'move left first' or 'move down first' spawnflags.
2) Set 'dest1' and 'dest2'. These are (x y z) vectors in worldspace corresponding to the first and second move, which will be scaled to the size of t_width and t_length.
3) Target a path_corner which targets a second path_corner. The door will move by its minimum corner like a func_train.

Activating this door with a trigger while it is opening will have no effect. Activating it while it is waiting open will reset its wait time (holding it open). Activating it while it is closing will cause it to reverse direction and open again. This lets you put a trigger_multiple in a secret room behind a func_door_secret to hold it open as long as a player is inside.

Flags:
"open_once" stays open
"1st_left" First move is opposite of v_right, then toward "angle"
"1st_down" First move is down, then toward "angle"
"no_shoot" only opened by trigger
"always_shoot" even if targeted, keep shootable

Keys:
"dmg" damage to inflict when blocked (default: 2). If a secret door has a targetname, it will only be opened by it's button or trigger, not by damage.
"speed" speed of first move, default 50
"speed2" speed of second move, defaults to "speed"
"sounds"
    1 = medieval
    2 = metal
    3 = base
"t_width" override distance for first move
"t_length" override distance for second move
"dest1"+"dest2" if both set, uses dest1 and dest2 for first and second move vectors, ignoring 1st_whatever spawnflags. still needs width and length.
"target" if pointed at a path_corner that targets a second path corner, will use these as the moves instead (relative to min corner, like a func_train) and ignore all of the above.
"wait"  # of seconds before coming back, default 5
*/
/*FGD
@SolidClass base(Appearflags, Targetname, Target, Func) = func_door_secret : 
"Secret door. Slides back, then to the side. 

There are three ways to configure how this door moves:
1) Set 'Angle'. The secret door will first move to the right of that angle by t_width units, then in the direction of that angle by t_length units. t_width and t_length default to the size of the door on those axes if left blank. The first move can be altered with the 'move left first' or 'move down first' spawnflags.
2) Set 'dest1' and 'dest2'. These are (x y z) vectors in worldspace corresponding to the first and second move, which will be scaled to the size of t_width and t_length.
3) Target a path_corner which targets a second path_corner. The door will move by its minimum corner like a func_train.

Activating this door with a trigger while it is opening will have no effect. Activating it while it is waiting open will reset its wait time (holding it open). Activating it while it is closing will cause it to reverse direction and open again. This lets you put a trigger_multiple in a secret room behind a func_door_secret to hold it open as long as a player is inside."
[
	angle(integer) : "Determines direction of SECOND move. FIRST move is to the RIGHT relative to 'angle'."
	t_width(integer) : "First move length"
	t_length(integer) : "Second move length"
	dmg(integer) : "Damage when blocked" : 2
	speed(integer) : "Speed of first move" : 50
	speed2(integer) : "Speed of second move" : 50
	wait(string) : "Wait before closing" : "2"
	dest1(string) : "Force vector for first move (requires dest2)"
	dest2(string) : "Force vector for second move (requires dest1)"
	sounds(choices) : "Sounds" : 3 =
	[
		1: "Medieval"
		2: "Metal"
		3: "Base"
	]
	message(string) : "Message"
	spawnflags(flags) = 
	[
		1 : "Open once" : 0
		2 : "Move left first" : 0
		4 : "Move down first" : 0
		8 : "Not shootable" : 0
        16 : "Always shootable" : 0
	]
]
*/
void () func_door_secret =
{
	if (!SUB_ShouldSpawn()) return;
	self.sprawlflags |= SFL_MOVINGSOLID;
	
	self.sounds = zeroconvertdefault(self.sounds, 3);
	
	if (self.sounds == 1)
	{
		self.noise1 = "doors/latch2.wav";
		self.noise2 = "doors/winch2.wav";
		self.noise3 = "doors/drclos4.wav";
	}
	if (self.sounds == 2)
	{
		self.noise1 = "doors/airdoor2.wav";
		self.noise2 = "doors/airdoor1.wav";
		self.noise3 = "doors/airdoor2.wav";
	}
	if (self.sounds == 3)
	{
		self.noise1 = "doors/basesec2.wav";
		self.noise2 = "doors/basesec1.wav";
		self.noise3 = "doors/basesec2.wav";
	}
	if (self.noise3 == string_null)
		self.noise3 = self.noise1;
	
	if (self.noise1 != string_null)
	{
		precache_sound_safe (self.noise1);
		precache_sound_safe (self.noise2);
		precache_sound_safe (self.noise3);
	}

	if (world.worldtype == 2)
	{
		door_set_sound(noise4, "doors/locked5.wav");
	}
	else
	{
		door_set_sound(noise4, "doors/locked4.wav");
	} 
	precache_sound_safe (self.noise4);
	
	self.dmg = zeroconvertdefault(self.dmg, 2);
	
	self.mangle = self.angles;
	self.angles = '0 0 0';
	self.solid = SOLID_BSP;
	self.movetype = MOVETYPE_PUSH;
	//self.classname = "door";
	setmodel (self, self.model);
	setorigin (self, self.origin);	
	
	self.touch = secret_touch;
	self.blocked = secret_blocked;
	
	if (self.speed <= 0) self.speed = 50;
	if (self.speed2 <= 0) self.speed2 = self.speed;
	
	if (self.spawnflags & SECRET_OPEN_ONCE) self.wait = -1;
	if (!self.wait) self.wait = 5;	// 5 seconds before closing
	
	if (self.style < 0)
	{
		self.style *= -1;
		self.copperflags |= CFL_INVLIGHT;
	}
	bmodel_lightstyle(self, 1);
	
	self.use = secretdoor_use;
	if ( !self.targetname || self.spawnflags & SECRET_YES_SHOOT)
	{
		if (!self.health)
			self.health = 10;
		self.max_health = self.health;
		self.takedamage = DAMAGE_YES;
		self.th_pain = secretdoor_pain;
		self.th_die = secretdoor_use;
	}
	self.oldorigin = self.origin;
	
	self.skin = self.frame;
	
	if (self.target != string_null)
	{
		self.think = secret_door_find;
		self.nextthink = self.ltime + 0.1;
	}
	else
		secret_door_moves();
}
