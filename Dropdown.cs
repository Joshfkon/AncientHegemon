using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using TMPro;
public class Dropdown: MonoBehaviour
{
//GameObject for Egypt Panel
//public GameObject EgyptPlayer;

//variables for civ
public int civ = 0;

public int numPlayers;

public int civ_player2 = 0;

void Start() {
//Loads data from PlayerPrefs - i.e. from revisous scenes or executions of the game
PlayerPrefs.GetInt("Civ", 0);  


    
}

//TMP Text Field for the output 
    public TextMeshProUGUI output;
//Outputs the Civ choice from the dropdown for the second player
    public TextMeshProUGUI output_Civ_player2;

//Function that outputs the text string of the region selected from the dropdown
    public void HandleInputData(int val) 
     {
         // Greece (1), Egyp(2)), Italia(3), Mesopotamia(4), (the rest to be added)

         // The dropdown optinos are numbered by unity. The first is 0, the second 1, and so on.
         // The ouput.text outputs a string dispayed on the mulitpayer lobby screen showing what civ you have selected
         // It will also set the value of the "civ" variable which I will save to the PlayerPrefs OnDestroy (that is, on sceene change) That way
         // I know what civ you are when moving to the strategy map scene.
            if (val == 0){
                output.text = "Greece";
                civ = 1;
                 Debug.Log("Greece was Choosen");

            }
            if (val == 1){
                output.text = "Egypt";
                civ = 2;
                Debug.Log("Egypt was Choosen");
            }
            if (val == 2){
                output.text = "Italia";
                civ = 3;
                Debug.Log("Italia was Choosen");
            }
            if (val == 3){
                output.text = "Mesopotamia";
                civ = 4;
                Debug.Log("Mesopotamia was Choosen");
            }
     }

public void HandleInputData_playertwo(int val) 
     {
         // Greece (1), Egyp(2)), Italia(3), Mesopotamia(4), (the rest to be added)

         // The dropdown optinos are numbered by unity. The first is 0, the second 1, and so on.
         // The ouput.text outputs a string dispayed on the mulitpayer lobby screen showing what civ you have selected
         // It will also set the value of the "civ" variable which I will save to the PlayerPrefs OnDestroy (that is, on sceene change) That way
         // I know what civ you are when moving to the strategy map scene.
            if (val == 0){
                output_Civ_player2.text = "Greece";
                civ_player2 = 1;
                 Debug.Log("Greece was Choosen");

            }
            if (val == 1){
                output_Civ_player2.text = "Egypt";
                civ_player2 = 2;
                Debug.Log("Egypt was Choosen");
            }
            if (val == 2){
                output_Civ_player2.text = "Italia";
                civ_player2 = 3;
                Debug.Log("Italia was Choosen");
            }
            if (val == 3){
                output_Civ_player2.text = "Mesopotamia";
                civ_player2 = 4;
                Debug.Log("Mesopotamia was Choosen");
            }
     }


//Calculate Number of players in the game

 void CalcNumPlayers()
 {
    if(civ_player2 == 0){
        numPlayers = 1;
        }
    if(civ_player2 != 0){
        numPlayers = 2;
    }

//Save numPlayers variable to Playerprefs so it will carry into the next scene
PlayerPrefs.SetInt("numPlayers", numPlayers);

}



void OnDestroy() {
    Debug.Log("GameStatus was destroyed.");

    //Save data to save file before destroyed (in scene change)

    // This will set the variabile "civ" to an interger. Plan is to give each civ a number. i.e. Greece == 1.
    // Then I will check this variable and display the approprate data. Hopefully this dosen't break in multiplayer.
    PlayerPrefs.SetInt("Civ", civ);
            
        }       
 }

