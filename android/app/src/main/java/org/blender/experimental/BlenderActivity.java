package org.blender.experimental;

import android.app.KeyguardManager;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.res.AssetManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.PowerManager;
import android.system.ErrnoException;
import android.system.Os;
import android.util.Log;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.widget.Toast;

import org.libsdl.app.SDLActivity;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * SDL host that unpacks Blender scripts/datafiles on first launch and points
 * the native runtime at the app sandbox via environment variables.
 */
public class BlenderActivity extends SDLActivity {
    private static final String TAG = "BlenderAndroid";
    private static final String RUNTIME_MARKER = "runtime_version.txt";
    private static final String RUNTIME_VERSION = "5.2.0-phone28";
    private static final String VERSION_DIR = "5.2";
    private AndroidStorage storage;

    @Override
    protected String[] getLibraries() {
        /* Load only SDL on the UI thread. libblender.so is ~1.4GB and
         * System.loadLibrary() during onCreate blocks the activity resume
         * handshake; Pixel then force-pauses us before a surface exists. */
        return new String[] {"SDL3"};
    }

    @Override
    protected String getMainSharedObject() {
        return getApplicationInfo().nativeLibraryDir + "/libblender.so";
    }

    @Override
    protected String getMainFunction() {
        return "SDL_main";
    }

    @Override
    protected String[] getArguments() {
        return new String[] {"--gpu-backend", "vulkan"};
    }

    @Override
    protected void main() {
        Log.i(TAG, "loading libblender.so on SDL thread");
        System.loadLibrary("blender");
        super.main();
    }

    @Override
    public void setOrientationBis(int w, int h, boolean resizable, String hint) {
        /* Keep the manifest lock. SDL hint changes restart the activity. */
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        File files = getFilesDir();
        File runtimeRoot = new File(files, "blender");
        try {
            unpackRuntimeIfNeeded(runtimeRoot);
            applyEnvironment(files, runtimeRoot);
        }
        catch (IOException | ErrnoException e) {
            Log.e(TAG, "Failed to prepare Blender runtime", e);
            Toast.makeText(
                    this,
                    "Blender could not unpack its runtime. Free storage and try again.",
                    Toast.LENGTH_LONG).show();
            finish();
            return;
        }
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
        super.onCreate(savedInstanceState);
        wakeScreenForLaunch();
        applyImmersiveUi();
        storage = new AndroidStorage(this);
        storage.applyPaths();
        storage.ensurePublicFolders();
        storage.start();
        handleOpenIntent(getIntent());
        Log.i(TAG, "onCreate finished (SDL only; blender.so deferred)");
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            applyImmersiveUi();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        wakeScreenForLaunch();
        applyImmersiveUi();
        if (storage != null) {
            storage.onResume();
        }
    }

    @Override
    protected void onDestroy() {
        if (storage != null) {
            storage.stop();
        }
        super.onDestroy();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (storage != null) {
            storage.onActivityResult(requestCode, resultCode, data);
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (storage != null) {
            storage.applyPaths();
            storage.ensurePublicFolders();
        }
    }

    private void wakeScreenForLaunch() {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true);
            setTurnScreenOn(true);
        }
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                | WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                | WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD);
        KeyguardManager keyguard = (KeyguardManager) getSystemService(KEYGUARD_SERVICE);
        if (keyguard != null && keyguard.isKeyguardLocked()) {
            keyguard.requestDismissKeyguard(this, null);
        }
        PowerManager power = (PowerManager) getSystemService(POWER_SERVICE);
        if (power != null) {
            PowerManager.WakeLock wake = power.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK | PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "blender:launch");
            wake.acquire(10 * 60 * 1000L);
        }
    }

    private void applyImmersiveUi() {
        Window window = getWindow();
        if (window == null) {
            return;
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
        window.clearFlags(WindowManager.LayoutParams.FLAG_FORCE_NOT_FULLSCREEN);
        if (Build.VERSION.SDK_INT >= 28) {
            WindowManager.LayoutParams attrs = window.getAttributes();
            attrs.layoutInDisplayCutoutMode =
                    Build.VERSION.SDK_INT >= 30 ?
                            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS :
                            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
            window.setAttributes(attrs);
        }
        window.setStatusBarColor(0x00000000);
        window.setNavigationBarColor(0x00000000);
        if (mLayout != null) {
            mLayout.setFitsSystemWindows(false);
            mLayout.setPadding(0, 0, 0, 0);
        }
        if (mSurface != null) {
            mSurface.setFitsSystemWindows(false);
            mSurface.setPadding(0, 0, 0, 0);
        }
        if (Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false);
            WindowInsetsController controller = window.getInsetsController();
            if (controller != null) {
                controller.hide(WindowInsets.Type.statusBars() | WindowInsets.Type.navigationBars());
                controller.setSystemBarsBehavior(
                        WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        } else {
            window.getDecorView().setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                            | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
        }
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleOpenIntent(intent);
    }

    private void handleOpenIntent(Intent intent) {
        if (intent == null) {
            return;
        }
        Uri uri = intent.getData();
        if (uri == null && Intent.ACTION_SEND.equals(intent.getAction())) {
            if (Build.VERSION.SDK_INT >= 33) {
                uri = intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri.class);
            } else {
                uri = intent.getParcelableExtra(Intent.EXTRA_STREAM);
            }
        }
        if (uri == null) {
            return;
        }
        try {
            Os.setenv("BLENDER_OPEN_URI", uri.toString(), true);
        }
        catch (ErrnoException e) {
            Log.w(TAG, "Could not set BLENDER_OPEN_URI", e);
        }
        if (storage != null) {
            storage.handleOpenUri(uri);
        }
    }

    private void applyEnvironment(File files, File runtimeRoot) throws ErrnoException, IOException {
        File versionRoot = new File(runtimeRoot, VERSION_DIR);
        File scripts = new File(versionRoot, "scripts");
        if (!scripts.isDirectory()) {
            throw new IOException("Missing unpacked scripts at " + scripts.getAbsolutePath());
        }

        File home = new File(files, "home");
        File config = new File(files, "config");
        File cache = new File(files, "cache");
        File userScripts = new File(files, "scripts");
        File tmp = new File(files, "tmp");
        home.mkdirs();
        config.mkdirs();
        cache.mkdirs();
        userScripts.mkdirs();
        tmp.mkdirs();

        /* Portable layout: {BLENDER_SYSTEM}/{version}/scripts|datafiles|python */
        Os.setenv("HOME", home.getAbsolutePath(), true);
        Os.setenv("TMPDIR", tmp.getAbsolutePath(), true);
        Os.setenv("XDG_CONFIG_HOME", config.getAbsolutePath(), true);
        Os.setenv("XDG_CACHE_HOME", cache.getAbsolutePath(), true);
        Os.setenv("BLENDER_SYSTEM", runtimeRoot.getAbsolutePath(), true);
        Os.setenv("BLENDER_USER_CONFIG", new File(config, "blender/" + VERSION_DIR).getAbsolutePath(), true);
        Os.setenv("BLENDER_USER_SCRIPTS", userScripts.getAbsolutePath(), true);
        Os.setenv("BLENDER_USER_DATAFILES", new File(files, "datafiles").getAbsolutePath(), true);
        Os.setenv("PYTHONHOME", new File(versionRoot, "python").getAbsolutePath(), true);
        Os.setenv("PYTHONPATH", new File(versionRoot, "python/lib/python3.13").getAbsolutePath(), true);
        Os.setenv("PYTHONUNBUFFERED", "1", true);
        Os.setenv("BLENDER_ANDROID", "1", true);
        new AndroidStorage(this).applyPaths();
    }

    private void unpackRuntimeIfNeeded(File runtimeRoot) throws IOException {
        File marker = new File(runtimeRoot, RUNTIME_MARKER);
        if (marker.isFile()) {
            String existing = readSmallFile(marker);
            if (RUNTIME_VERSION.equals(existing.trim())) {
                return;
            }
        }

        Log.i(TAG, "Unpacking Blender runtime into " + runtimeRoot.getAbsolutePath());
        if (runtimeRoot.exists()) {
            deleteRecursive(runtimeRoot);
        }
        runtimeRoot.mkdirs();

        AssetManager assets = getAssets();
        copyAssetTree(assets, "blender", runtimeRoot);

        try (FileOutputStream out = new FileOutputStream(marker)) {
            out.write(RUNTIME_VERSION.getBytes("UTF-8"));
        }
    }

    private static void copyAssetTree(AssetManager assets, String assetPath, File destDir)
            throws IOException
    {
        String[] children = assets.list(assetPath);
        if (children == null) {
            return;
        }
        if (children.length == 0) {
            destDir.getParentFile().mkdirs();
            try (InputStream in = assets.open(assetPath); OutputStream out = new FileOutputStream(destDir)) {
                byte[] buf = new byte[64 * 1024];
                int n;
                while ((n = in.read(buf)) > 0) {
                    out.write(buf, 0, n);
                }
            }
            catch (IOException e) {
                destDir.mkdirs();
            }
            return;
        }

        destDir.mkdirs();
        for (String child : children) {
            String childAsset = assetPath + "/" + child;
            copyAssetTree(assets, childAsset, new File(destDir, child));
        }
    }

    private static String readSmallFile(File file) throws IOException {
        long len = file.length();
        if (len <= 0 || len > 256) {
            return "";
        }
        byte[] data = new byte[(int) len];
        try (InputStream in = new java.io.FileInputStream(file)) {
            int off = 0;
            while (off < data.length) {
                int n = in.read(data, off, data.length - off);
                if (n < 0) {
                    break;
                }
                off += n;
            }
        }
        return new String(data, "UTF-8");
    }

    private static void deleteRecursive(File file) {
        File[] children = file.listFiles();
        if (children != null) {
            for (File child : children) {
                deleteRecursive(child);
            }
        }
        file.delete();
    }
}
