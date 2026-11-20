// Exercise the Java API in the installed jar. No producer classpath is used.
import com.cjprof.jni.Cjprof;
import java.util.Collections;

class CjprofInstalled {
    public static void main(String[] args) {
        Cjprof.initialize();
        if (!Cjprof.queryAllHeapSnapshot().isEmpty()) throw new AssertionError("unexpected initial snapshot");
        if (!Cjprof.parseHeapSnapshotFiles(Collections.singletonList(args[0]))) throw new AssertionError("heap file was not parsed");
        long id = Cjprof.getSnapshotIDByFilePath(args[0]);
        if (Cjprof.queryAllHeapSnapshot().size() != 1 || Cjprof.getConstructorNodesBySnapshotID(id).isEmpty())
            throw new AssertionError("heap graph not available through JNI");
        Cjprof.cleanHeapSnapshotFiles(Collections.singletonList(id));
        if (!Cjprof.queryAllHeapSnapshot().isEmpty()) throw new AssertionError("cleanup did not remove the snapshot");
        System.out.println("CJPROF_INSTALLED_HEAP_GRAPH");
    }
}
