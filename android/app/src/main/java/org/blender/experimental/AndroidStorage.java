package org.blender.experimental;

import android.Manifest;
import android.app.Activity;
import android.content.ContentResolver;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.OpenableColumns;
import android.provider.Settings;
import android.system.ErrnoException;
import android.system.Os;
import android.util.Log;
import android.widget.Toast;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/**
 * Phone storage: runtime permissions, all-files access, SAF picker, and
 * content:// copies so Blender's native file browser can use real paths.
 */
final class AndroidStorage {
    static final String TAG = "BlenderStorage";
    static final int REQ_RUNTIME = 4301;
    static final int REQ_OPEN = 4302;
    static final int REQ_SAVE = 4303;

    private static final String PREFS = "blender_storage";
    private static final String ASKED_ALL_FILES = "asked_all_files";

    private final Activity activity;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable poll = this::pollCommands;
    private boolean started;

    AndroidStorage(Activity activity) {
        this.activity = activity;
    }

    void start() {
        if (started) {
            return;
        }
        started = true;
        applyPaths();
        ensurePublicFolders();
        /* Do not prompt for permissions here. The system dialog pauses this
         * Activity and destroys the SDL/Vulkan surface before Blender starts. */
        handler.postDelayed(poll, 500);
    }

    void stop() {
        handler.removeCallbacks(poll);
        started = false;
    }

    void onResume() {
        applyPaths();
        ensurePublicFolders();
    }

    void requestAccess(boolean forcePrompt) {
        applyPaths();
        ensurePublicFolders();
        if (forcePrompt) {
            requestRuntimePermissions();
        }
        /* Do not leave the Activity unless the user asked. Opening Settings or
         * a file picker destroys the Vulkan surface and used to abort Blender. */
        if (forcePrompt && needsAllFilesAccess()) {
            SharedPreferences prefs = activity.getSharedPreferences(PREFS, Activity.MODE_PRIVATE);
            prefs.edit().putBoolean(ASKED_ALL_FILES, true).apply();
            openAllFilesSettings();
        }
    }

    boolean hasAllFilesAccess() {
        if (Build.VERSION.SDK_INT < 30) {
            return true;
        }
        return Environment.isExternalStorageManager();
    }

    boolean needsAllFilesAccess() {
        return Build.VERSION.SDK_INT >= 30 && !hasAllFilesAccess();
    }

    void applyPaths() {
        File root = publicRoot();
        File downloads = new File(root, "Download");
        File documents = new File(root, "Documents");
        File pictures = new File(root, "Pictures");
        File dcim = new File(root, "DCIM");
        File movies = new File(root, "Movies");
        File music = new File(root, "Music");
        File blends = new File(downloads, "Blender");
        File extApp = activity.getExternalFilesDir(null);
        try {
            Os.setenv("EXTERNAL_STORAGE", root.getAbsolutePath(), true);
            Os.setenv("BLENDER_ANDROID_STORAGE", root.getAbsolutePath(), true);
            Os.setenv("BLENDER_ANDROID_DOWNLOADS", downloads.getAbsolutePath(), true);
            Os.setenv("BLENDER_ANDROID_DOCUMENTS", documents.getAbsolutePath(), true);
            Os.setenv("BLENDER_ANDROID_PICTURES", pictures.getAbsolutePath(), true);
            Os.setenv("BLENDER_ANDROID_DCIM", dcim.getAbsolutePath(), true);
            Os.setenv("BLENDER_ANDROID_MOVIES", movies.getAbsolutePath(), true);
            Os.setenv("BLENDER_ANDROID_MUSIC", music.getAbsolutePath(), true);
            Os.setenv("BLENDER_ANDROID_BLENDS", blends.getAbsolutePath(), true);
            if (extApp != null) {
                Os.setenv("BLENDER_ANDROID_APP_FILES", extApp.getAbsolutePath(), true);
            }
            Os.setenv("BLENDER_ANDROID_HAS_STORAGE", hasAllFilesAccess() ? "1" : "0", true);
        }
        catch (ErrnoException e) {
            Log.w(TAG, "Could not export storage paths", e);
        }
        writeUserDirs(activity.getFilesDir());
        writeDefaultBookmarks(activity.getFilesDir());
    }

    void ensurePublicFolders() {
        File root = publicRoot();
        mkdirsQuiet(new File(root, "Download/Blender"));
        mkdirsQuiet(new File(root, "Documents/Blender"));
        File inbox = new File(activity.getFilesDir(), "inbox");
        mkdirsQuiet(inbox);
        File ext = activity.getExternalFilesDir(null);
        if (ext != null) {
            mkdirsQuiet(new File(ext, "Blender"));
        }
    }

    File handleOpenUri(Uri uri) {
        if (uri == null) {
            return null;
        }
        takePersistableRead(uri);
        File dest = copyUriToReadableFile(uri);
        if (dest != null) {
            writeText(pendingOpenFile(), dest.getAbsolutePath());
            try {
                Os.setenv("BLENDER_OPEN_PATH", dest.getAbsolutePath(), true);
            }
            catch (ErrnoException e) {
                Log.w(TAG, "Could not set BLENDER_OPEN_PATH", e);
            }
        }
        return dest;
    }

    void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != REQ_OPEN && requestCode != REQ_SAVE) {
            return;
        }
        if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null) {
            writeText(resultFile(), "CANCEL");
            return;
        }
        Uri uri = data.getData();
        takePersistableRead(uri);
        if (requestCode == REQ_OPEN) {
            File dest = copyUriToReadableFile(uri);
            if (dest != null) {
                writeText(pendingOpenFile(), dest.getAbsolutePath());
                writeText(resultFile(), dest.getAbsolutePath());
            } else {
                writeText(resultFile(), "ERROR\nCould not copy the selected file.");
            }
            return;
        }
        File source = readFirstLine(saveSourceFile());
        if (source == null || !source.isFile()) {
            writeText(resultFile(), "ERROR\nNothing to save.");
            return;
        }
        if (copyFileToUri(source, uri)) {
            writeText(resultFile(), source.getAbsolutePath());
        } else {
            writeText(resultFile(), "ERROR\nCould not write the selected file.");
        }
    }

    private void pollCommands() {
        File cmd = commandFile();
        if (cmd.isFile()) {
            String text = readSmall(cmd);
            //noinspection ResultOfMethodCallIgnored
            cmd.delete();
            String[] lines = text.split("\\r?\\n", 3);
            String action = lines.length > 0 ? lines[0].trim() : "";
            String extra = lines.length > 1 ? lines[1].trim() : "";
            if ("open".equals(action)) {
                launchOpenPicker();
            } else if ("save".equals(action)) {
                if (!extra.isEmpty()) {
                    writeText(saveSourceFile(), extra);
                }
                launchSavePicker(new File(extra).getName());
            } else if ("grant".equals(action)) {
                requestAccess(true);
            }
        }
        handler.postDelayed(poll, 400);
    }

    private void requestRuntimePermissions() {
        if (Build.VERSION.SDK_INT < 23) {
            return;
        }
        List<String> needed = new ArrayList<>();
        if (Build.VERSION.SDK_INT >= 33) {
            addMissing(needed, Manifest.permission.READ_MEDIA_IMAGES);
            addMissing(needed, Manifest.permission.READ_MEDIA_VIDEO);
            addMissing(needed, Manifest.permission.READ_MEDIA_AUDIO);
        } else {
            addMissing(needed, Manifest.permission.READ_EXTERNAL_STORAGE);
            addMissing(needed, Manifest.permission.WRITE_EXTERNAL_STORAGE);
        }
        if (!needed.isEmpty()) {
            activity.requestPermissions(needed.toArray(new String[0]), REQ_RUNTIME);
        }
    }

    private void addMissing(List<String> out, String permission) {
        if (activity.checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
            out.add(permission);
        }
    }

    private void openAllFilesSettings() {
        Toast.makeText(
                activity,
                "Allow Blender to access all files so you can open and save on this phone.",
                Toast.LENGTH_LONG).show();
        try {
            Intent intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
            intent.setData(Uri.parse("package:" + activity.getPackageName()));
            activity.startActivity(intent);
        }
        catch (Exception e) {
            try {
                activity.startActivity(new Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION));
            }
            catch (Exception ignored) {
                Log.w(TAG, "Could not open all-files settings", e);
            }
        }
    }

    private void launchOpenPicker() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[] {
                "application/x-blender",
                "application/octet-stream",
                "image/*",
                "audio/*",
                "video/*",
                "*/*"
        });
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION
                | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        try {
            activity.startActivityForResult(Intent.createChooser(intent, "Open from phone"), REQ_OPEN);
        }
        catch (Exception e) {
            writeText(resultFile(), "ERROR\nNo file picker is available.");
        }
    }

    private void launchSavePicker(String suggestedName) {
        if (suggestedName == null || suggestedName.isEmpty()) {
            suggestedName = "untitled.blend";
        }
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("application/octet-stream");
        intent.putExtra(Intent.EXTRA_TITLE, suggestedName);
        intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                | Intent.FLAG_GRANT_READ_URI_PERMISSION
                | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        try {
            activity.startActivityForResult(Intent.createChooser(intent, "Save to phone"), REQ_SAVE);
        }
        catch (Exception e) {
            writeText(resultFile(), "ERROR\nNo file picker is available.");
        }
    }

    private File copyUriToReadableFile(Uri uri) {
        String name = queryDisplayName(uri);
        if (name == null || name.isEmpty()) {
            name = "opened.bin";
        }
        name = sanitizeName(name);
        File destDir = preferredBlendsDir();
        mkdirsQuiet(destDir);
        File dest = uniqueFile(destDir, name);
        try (InputStream in = activity.getContentResolver().openInputStream(uri);
             OutputStream out = new FileOutputStream(dest)) {
            if (in == null) {
                return null;
            }
            copyStream(in, out);
            return dest;
        }
        catch (IOException e) {
            Log.w(TAG, "Copy URI failed: " + uri, e);
            return null;
        }
    }

    private boolean copyFileToUri(File source, Uri uri) {
        try (InputStream in = new FileInputStream(source);
             OutputStream out = activity.getContentResolver().openOutputStream(uri, "w")) {
            if (out == null) {
                return false;
            }
            copyStream(in, out);
            return true;
        }
        catch (IOException e) {
            Log.w(TAG, "Copy to URI failed: " + uri, e);
            return false;
        }
    }

    private void takePersistableRead(Uri uri) {
        try {
            activity.getContentResolver().takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        }
        catch (SecurityException | UnsupportedOperationException ignored) {
        }
    }

    private String queryDisplayName(Uri uri) {
        ContentResolver resolver = activity.getContentResolver();
        try (Cursor cursor = resolver.query(uri, new String[] {OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (index >= 0) {
                    return cursor.getString(index);
                }
            }
        }
        catch (Exception ignored) {
        }
        String last = uri.getLastPathSegment();
        return last != null ? last : "opened.bin";
    }

    private File preferredBlendsDir() {
        File publicBlends = new File(publicRoot(), "Download/Blender");
        if (publicBlends.isDirectory() || publicBlends.mkdirs()) {
            return publicBlends;
        }
        File ext = activity.getExternalFilesDir(null);
        if (ext != null) {
            File folder = new File(ext, "Blender");
            mkdirsQuiet(folder);
            return folder;
        }
        File inbox = new File(activity.getFilesDir(), "inbox");
        mkdirsQuiet(inbox);
        return inbox;
    }

    static File publicRoot() {
        File dir = Environment.getExternalStorageDirectory();
        if (dir != null) {
            return dir;
        }
        return new File("/storage/emulated/0");
    }

    private void writeUserDirs(File filesDir) {
        File config = new File(filesDir, "config");
        mkdirsQuiet(config);
        File root = publicRoot();
        String text =
                "XDG_DESKTOP_DIR=\"" + new File(root, "Download").getAbsolutePath() + "\"\n"
                + "XDG_DOCUMENTS_DIR=\"" + new File(root, "Documents").getAbsolutePath() + "\"\n"
                + "XDG_DOWNLOAD_DIR=\"" + new File(root, "Download").getAbsolutePath() + "\"\n"
                + "XDG_PICTURES_DIR=\"" + new File(root, "Pictures").getAbsolutePath() + "\"\n"
                + "XDG_VIDEOS_DIR=\"" + new File(root, "Movies").getAbsolutePath() + "\"\n"
                + "XDG_MUSIC_DIR=\"" + new File(root, "Music").getAbsolutePath() + "\"\n";
        writeText(new File(config, "user-dirs.dirs"), text);
    }

    private void writeDefaultBookmarks(File filesDir) {
        File dest = new File(filesDir, "config/blender/5.2/bookmarks.txt");
        if (dest.isFile()) {
            return;
        }
        mkdirsQuiet(dest.getParentFile());
        File root = publicRoot();
        String text = "[Bookmarks]\n"
                + "!Phone Storage\n" + root.getAbsolutePath() + "\n"
                + "!Download\n" + new File(root, "Download").getAbsolutePath() + "\n"
                + "!Blender Files\n" + new File(root, "Download/Blender").getAbsolutePath() + "\n"
                + "!Documents\n" + new File(root, "Documents").getAbsolutePath() + "\n"
                + "!Pictures\n" + new File(root, "Pictures").getAbsolutePath() + "\n"
                + "!Camera\n" + new File(root, "DCIM").getAbsolutePath() + "\n"
                + "!Movies\n" + new File(root, "Movies").getAbsolutePath() + "\n"
                + "!Music\n" + new File(root, "Music").getAbsolutePath() + "\n"
                + "[Recent]\n";
        writeText(dest, text);
    }

    private File commandFile() {
        return new File(activity.getFilesDir(), "android_cmd.txt");
    }

    private File resultFile() {
        return new File(activity.getFilesDir(), "android_result.txt");
    }

    private File pendingOpenFile() {
        return new File(activity.getFilesDir(), "pending_open.txt");
    }

    private File saveSourceFile() {
        return new File(activity.getFilesDir(), "android_save_source.txt");
    }

    private static File uniqueFile(File dir, String name) {
        File dest = new File(dir, name);
        if (!dest.exists()) {
            return dest;
        }
        String stem = name;
        String ext = "";
        int dot = name.lastIndexOf('.');
        if (dot > 0) {
            stem = name.substring(0, dot);
            ext = name.substring(dot);
        }
        for (int i = 1; i < 1000; i++) {
            dest = new File(dir, stem + "_" + i + ext);
            if (!dest.exists()) {
                return dest;
            }
        }
        return new File(dir, stem + "_" + System.currentTimeMillis() + ext);
    }

    private static String sanitizeName(String name) {
        return name.replace('\\', '_').replace('/', '_').replace('\0', '_');
    }

    private static void copyStream(InputStream in, OutputStream out) throws IOException {
        byte[] buf = new byte[64 * 1024];
        int n;
        while ((n = in.read(buf)) > 0) {
            out.write(buf, 0, n);
        }
        out.flush();
    }

    private static void mkdirsQuiet(File dir) {
        if (dir != null && !dir.isDirectory()) {
            //noinspection ResultOfMethodCallIgnored
            dir.mkdirs();
        }
    }

    private static void writeText(File file, String text) {
        try (FileOutputStream out = new FileOutputStream(file)) {
            out.write(text.getBytes(StandardCharsets.UTF_8));
        }
        catch (IOException e) {
            Log.w(TAG, "Write failed: " + file, e);
        }
    }

    private static String readSmall(File file) {
        try (InputStream in = new FileInputStream(file)) {
            byte[] data = new byte[(int) Math.min(file.length(), 8192)];
            int n = in.read(data);
            if (n <= 0) {
                return "";
            }
            return new String(data, 0, n, StandardCharsets.UTF_8);
        }
        catch (IOException e) {
            return "";
        }
    }

    private static File readFirstLine(File file) {
        if (!file.isFile()) {
            return null;
        }
        String text = readSmall(file).split("\\r?\\n", 2)[0].trim();
        return text.isEmpty() ? null : new File(text);
    }
}
