import com.sun.source.tree.*;
import com.sun.source.util.JavacTask;
import com.sun.source.util.TreePathScanner;
import com.sun.source.util.TreeScanner;
import com.sun.source.util.Trees;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.regex.Pattern;
import javax.lang.model.element.Modifier;
import javax.tools.Diagnostic;
import javax.tools.DiagnosticCollector;
import javax.tools.JavaFileObject;
import javax.tools.ToolProvider;

/** Parse-only inventory: no Android classpath, annotation processing, or code execution. */
public final class JavaHardcodeScanner {
    public static void main(String[] args) throws Exception {
        var compiler = ToolProvider.getSystemJavaCompiler();
        if (compiler == null) throw new IllegalStateException("A full JDK is required");
        var diagnostics = new DiagnosticCollector<JavaFileObject>();
        try (var manager = compiler.getStandardFileManager(diagnostics, null, StandardCharsets.UTF_8)) {
            var paths = java.util.Arrays.stream(args).map(Path::of)
                    .map(path -> path.toAbsolutePath().normalize()).toList();
            var task = (JavacTask) compiler.getTask(null, manager, diagnostics,
                    List.of("-proc:none"), null, manager.getJavaFileObjectsFromPaths(paths));
            var units = task.parse();
            if (diagnostics.getDiagnostics().stream().anyMatch(d -> d.getKind() == Diagnostic.Kind.ERROR)) {
                throw new IllegalArgumentException("Java source syntax errors prevent a complete audit");
            }
            var positions = Trees.instance(task).getSourcePositions();
            for (var unit : units) {
                Path path = Path.of(unit.getSourceFile().toUri()).toAbsolutePath().normalize();
                int fileIndex = paths.indexOf(path);
                if (fileIndex < 0) throw new IllegalStateException("Unexpected compiler source");
                String content = Files.readString(path);
                new TreePathScanner<Void, Void>() {
                    @Override public Void visitVariable(VariableTree node, Void unused) {
                        if (node.getModifiers().getFlags().contains(Modifier.FINAL)
                                && Boolean.TRUE.equals(new TreeScanner<Boolean, Void>() {
                                    @Override public Boolean visitLiteral(LiteralTree literal, Void ignored) {
                                        return literal.getValue() instanceof Number
                                                || literal.getValue() instanceof String;
                                    }
                                    @Override public Boolean reduce(Boolean left, Boolean right) {
                                        return Boolean.TRUE.equals(left) || Boolean.TRUE.equals(right);
                                    }
                                }.scan(node.getInitializer(), null))) {
                            int end = Math.toIntExact(positions.getEndPosition(unit, node));
                            int newline = content.indexOf('\n', end);
                            String tail = content.substring(end, newline < 0 ? content.length() : newline).stripLeading();
                            var annotation = Pattern.compile("^//\\s*hardcode:\\s*(HC-\\d{3})\\b").matcher(tail);
                            long line = unit.getLineMap().getLineNumber(positions.getStartPosition(unit, node));
                            System.out.println(fileIndex + "\t" + line + "\t" + node.getName()
                                    + "\t" + (annotation.find() ? annotation.group(1) : "-"));
                        }
                        return super.visitVariable(node, unused);
                    }
                }.scan(unit, null);
            }
        }
    }
}
