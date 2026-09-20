package org.blender.experimental;

import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.res.AssetManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
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
        return new String[] {"SDL3", "blender"};
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
    public void setOrientationBis(int w, int h, boolean resizable, String hint) {
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
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
        super.onCreate(savedInstanceState);
        applyImmersiveUi();
        storage = new AndroidStorage(this);
        storage.applyPaths();
        storage.ensurePublicFolders();
        storage.start();
        handleOpenIntent(getIntent());
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
