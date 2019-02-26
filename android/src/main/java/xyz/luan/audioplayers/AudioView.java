package xyz.luan.audioplayers;

import android.content.Context;

/**
 * Created by Woody Guo on 2019/2/26.
 */
public interface AudioView {
    Context getApplicationContext();

    void onStart(WrappedMediaPlayer player);
    void onPause(WrappedMediaPlayer player);
    void onStop(WrappedMediaPlayer player);
    void onSourceSet(WrappedMediaPlayer player, String source);

    void onComplete(WrappedMediaPlayer player);

    void onProgressUpdate(WrappedMediaPlayer player, int duration, int position);

    void onSeekComplete(WrappedMediaPlayer player);
}
