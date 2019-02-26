package xyz.luan.audioplayers;

/**
 * Created by Woody Guo on 2019/2/26.
 */
public interface AudioView {
    void onPlay(WrappedMediaPlayer player);
    void onDurationUpdate(WrappedMediaPlayer player, int duration);
    void onPositionUpdate(WrappedMediaPlayer player, int position);
    void onComplete(WrappedMediaPlayer player);
    void onSeekComplete(WrappedMediaPlayer player);
}
