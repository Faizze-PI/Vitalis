import java.io.StringReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilderFactory;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.xml.sax.InputSource;
import org.xml.sax.SAXParseException;
import org.xml.sax.helpers.DefaultHandler;

public final class TransferCoverageGate {
    private static final String PACKAGE = "com/vitalis/vitalis_app/transfer";
    // G3 acceptance requires 90% line coverage for transfer/recovery components.
    private static final int REQUIRED_LINE_PERCENT = 90;

    public static void main(String[] args) {
        if (args.length != 1) {
            System.err.println("Usage: TransferCoverageGate <JaCoCo XML report>");
            System.exit(2);
        }
        Map<String, Integer> required = new HashMap<>();
        for (String source : List.of("TransferFailureCode", "TransferManifestStore",
                "TransferStopWorker", "TransferWorker", "TransferScheduler",
                "TransferExecutionResult", "TransferController", "TransferStopDisposition",
                "TransferRunControl", "TransferEngine", "TransferManifest",
                "TransferActionReceiver", "TransferNotifications", "TransferWriterLease",
                "TransferJobService", "TransferNotificationIds", "TransferRecoveryAction",
                "TransferStoragePreflight")) {
            required.put(source + ".java", REQUIRED_LINE_PERCENT);
        }
        List<String> failures;
        try {
            failures = evaluate(Files.readString(Path.of(args[0])), required);
        } catch (Exception unavailable) {
            failures = List.of("Coverage report unavailable: " + unavailable.getClass().getSimpleName());
        }
        failures.forEach(System.err::println);
        if (!failures.isEmpty()) System.exit(1);
        System.out.println("Transfer recovery coverage passed for " + required.size() + " required sources");
    }

    static List<String> evaluate(String xml, Map<String, Integer> required) {
        List<String> failures = new ArrayList<>();
        if (required.isEmpty()) return List.of("No coverage requirements supplied");
        try {
            DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
            factory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
            factory.setFeature("http://xml.org/sax/features/external-general-entities", false);
            factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
            factory.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false);
            factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "");
            factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "");
            factory.setXIncludeAware(false);
            var builder = factory.newDocumentBuilder();
            builder.setErrorHandler(new DefaultHandler() {
                @Override public void error(SAXParseException error) throws SAXParseException { throw error; }
                @Override public void fatalError(SAXParseException error) throws SAXParseException { throw error; }
            });
            var document = builder.parse(new InputSource(new StringReader(xml)));
            if (!"report".equals(document.getDocumentElement().getTagName())) {
                return List.of("Not a JaCoCo report");
            }
            if (document.getDoctype() != null && document.getDoctype().getInternalSubset() != null) {
                return List.of("Internal XML declarations are not accepted");
            }
            Map<String, Element> sources = new HashMap<>();
            var nodes = document.getElementsByTagName("sourcefile");
            for (int index = 0; index < nodes.getLength(); index++) {
                Element source = (Element) nodes.item(index);
                if (!(source.getParentNode() instanceof Element parent)
                        || !"package".equals(parent.getTagName())
                        || !PACKAGE.equals(parent.getAttribute("name"))) continue;
                String name = source.getAttribute("name");
                if (sources.putIfAbsent(name, source) != null) failures.add("Duplicate source: " + name);
            }
            for (var requirement : required.entrySet()) {
                Element source = sources.get(requirement.getKey());
                if (source == null) {
                    failures.add("Missing coverage: " + requirement.getKey());
                    continue;
                }
                Element lines = null;
                for (Node child = source.getFirstChild(); child != null; child = child.getNextSibling()) {
                    if (child instanceof Element counter && "counter".equals(counter.getTagName())
                            && "LINE".equals(counter.getAttribute("type"))) {
                        if (lines != null) throw new IllegalArgumentException("Duplicate line counter");
                        lines = counter;
                    }
                }
                if (lines == null) throw new IllegalArgumentException("Missing line counter");
                long missed = Long.parseLong(lines.getAttribute("missed"));
                long covered = Long.parseLong(lines.getAttribute("covered"));
                long total = Math.addExact(missed, covered);
                if (missed < 0L || covered < 0L || total <= 0L) throw new IllegalArgumentException("Invalid counters");
                if (100.0 * covered / total < requirement.getValue()) {
                    failures.add(requirement.getKey() + ": " + covered + "/" + total
                            + " lines; requires " + requirement.getValue() + "%");
                }
            }
        } catch (Exception invalid) {
            failures.add("Invalid coverage report: " + invalid.getClass().getSimpleName());
        }
        return failures;
    }
}
