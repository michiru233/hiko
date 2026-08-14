package top.voicehub.kikoeru;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(KikoeruPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
