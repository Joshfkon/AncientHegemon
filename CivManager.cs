using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using TMPro;

public class CivManager : MonoBehaviour
{

//variables for civ which should be stored in PlayerPrefs
public int civ;
//TMP Text Field for the output Civ Name 
public TextMeshProUGUI yourCiv;
public TextMeshProUGUI yourLeaderOf;

public TextMeshProUGUI EventTitle;

public TextMeshProUGUI EventDescription;

public int turnloop = 0;


public TextMeshProUGUI CollectResources;

public int EventNumber;

public string yourname;
public void Turn() {
    


//To Do on start: 

//Determine who's turn it is. 

// Display "Start of Turn Panel" for the Player whose turn it is.

    //First, show inputs for unit placement on the map. i.e. Allow the player to enter that they have x military units in Egypt and y units in Thrace

    //Calculate the Fear/Resentment/Credibility variables for each region - i.e. how each region feels about your empire. 
    //Show any changes from the regions - i.e. a loss of units might reduce the fear of a region that they rebel or stop paying tribute. Alternativly they might send a gift. 

    //Generate a Random Event which may modify the resources collected
    //Calculate and the display the resources to collect (or shortfalls casuing desertment and/or population starvation) from each region based on the calculated population,
    //...unit placement, and event modifier 
    
    
//1. Determine who's turn it is.

if(turnloop == 0){

PlayerOneTurn();
turnloop = turnloop + 1; 
Debug.Log("it's player " + turnloop + "'s turn");


}





//Generates a random number that coresponds to an event. Dispays the even and a description of it. Later I will modify other variables based on the event.

    void GenerateEvent(){

        EventNumber = Random.Range (1, 7);
        Debug.Log("Random number is " + EventNumber);

        if (EventNumber == 1)
        {
            EventTitle.text = "FAMINE!";
            EventDescription.text = "You have only produced 2/3 of your expected grain resources this turn";
        }

        if (EventNumber == 2)
        {
            EventTitle.text = "PLAGUE";
            EventDescription.text = "1/5 of your population has died from the plague";
        }
        
        if (EventNumber == 3)
        {
            EventTitle.text = "GOOD HARVEST";
            EventDescription.text = "Double grain production this turn";
        }

        if (EventNumber == 4)
        {
            EventTitle.text = "GOLD MINE";
            EventDescription.text = "You've discovered gold in your empire! One gold added to supply from now on";
        }

        if (EventNumber == 5)
        {
            EventTitle.text = "BAD OMEN";
            EventDescription.text = "The sacred chickens have refused to eat or drink. You are unable to initiate an attack this turn";
        }

        if (EventNumber == 6)
        {
            EventTitle.text = "METEORITE";
            EventDescription.text = "You find a strange metal rock in a crater. A gift from the gods. Collect 1 Iron regardless of civilizational age";
        }
        if (EventNumber == 7)
        {
            EventTitle.text = "LEADER DIES";
            EventDescription.text = "The leader of your civilization has died of natural causes.";
        }
}


//Loads data from PlayerPrefs - i.e. from revisous scenes or executions of the game
// Greece (1), Egyp(2)), Italia(3), Mesopotamia(4), (the rest to be added)

//variables for civ which should be stored in PlayerPrefs
 
void PlayerOneTurn(){

 civ = PlayerPrefs.GetInt("Civ");  
 yourname = PlayerPrefs.GetString(yourname);
 Debug.Log(yourname + "This is what it sees as your name Civmanager");

    if (civ == 0)
    {
     yourCiv.text = "Greece"; 
     yourLeaderOf.text = PlayerPrefs.GetString(yourname,  "civ your Name") + " You are the leader of Greece";
      Debug.Log("civ= 0 was Choosen");
    }

    if (civ == 1)
    {
     yourCiv.text = "Greece"; 
      yourLeaderOf.text = PlayerPrefs.GetString(yourname, "civ your Name") + " You are the leader of Greece";
      Debug.Log("Greece was Choosen in scene 2");
    }

    if (civ == 2)
    {
     yourCiv.text = "Egypt"; 
      yourLeaderOf.text = PlayerPrefs.GetString(yourname, "civ your Name") + " You are the leader of Egypt";

    }
       if (civ == 3)
    {
     yourCiv.text = "Italia"; 
     yourLeaderOf.text = PlayerPrefs.GetString(yourname,  "civ your Name") + " You are the leader of Italia";
    }

    GenerateEvent();
}
}
}

