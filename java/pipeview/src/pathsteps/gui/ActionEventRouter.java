package pathsteps.gui;
import java.awt.event.*;

import pathsteps.common.*;

/**
 * Generic class to forward action events onto central handler.
**/
public class ActionEventRouter 
extends EventRouter
implements ActionListener
{
  public ActionEventRouter(Application handler, String key){
    super(handler, key);
  }
  
  public void actionPerformed(ActionEvent event){
    getHandler().notifyEventForKey(getKey());
  }
}
