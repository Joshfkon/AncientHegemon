using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using TMPro;



public class LeaderName : MonoBehaviour
{
   public string theName;
   public string yourname;

   public string Player2name;

   public string TheNamePlayer2;

   //Input for player 1 Name
   public GameObject inputField;

   //Input for player 2 Name
   public GameObject inputField_player2;
   
   //Display Player 1 Name
   public GameObject textDisplay;
 
 
//Display Player 2 Name
   public GameObject textDisplay_player2;


   public void StoreName()
   {
       theName = inputField.GetComponent<Text>().text;
       PlayerPrefs.SetString(yourname, inputField.GetComponent<Text>().text);
       PlayerPrefs.Save();
       textDisplay.GetComponent<Text>().text = theName;
       Debug.Log(yourname + "player 1 name");
     
       TheNamePlayer2 = inputField_player2.GetComponent<Text>().text;
       PlayerPrefs.SetString(Player2name, inputField_player2.GetComponent<Text>().text);
       PlayerPrefs.Save();
       textDisplay_player2.GetComponent<Text>().text = TheNamePlayer2;
       Debug.Log(TheNamePlayer2 + "player 2 name ");

   }
void Update() {

}
  
}