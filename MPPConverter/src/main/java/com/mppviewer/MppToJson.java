package com.mppviewer;

import net.sf.mpxj.ProjectFile;
import net.sf.mpxj.reader.UniversalProjectReader;
import net.sf.mpxj.json.JsonWriter;

import java.io.File;

public class MppToJson {
    public static void main(String[] args) {
        if (args.length >= 3 && "--plan-to-mspdi".equals(args[0])) {
            try {
                MspdiExport.run(args[1], args[2]);
                System.out.println("OK");
            } catch (Exception e) {
                System.err.println("Error exporting MSPDI: " + e.getMessage());
                e.printStackTrace(System.err);
                System.exit(1);
            }
            return;
        }

        if (args.length < 2) {
            System.err.println("Usage: MppToJson <input.mpp> <output.json>");
            System.err.println("       MppToJson --plan-to-mspdi <plan.json> <output.xml>");
            System.exit(1);
        }

        String inputPath = args[0];
        String outputPath = args[1];

        try {
            File inputFile = new File(inputPath);
            if (!inputFile.exists()) {
                System.err.println("Input file not found: " + inputPath);
                System.exit(1);
            }

            ProjectFile project = new UniversalProjectReader().read(inputFile);
            if (project == null) {
                System.err.println("Failed to read project file: " + inputPath);
                System.exit(1);
            }

            JsonWriter writer = new JsonWriter();
            writer.setPretty(true);
            writer.write(project, new File(outputPath));

            System.out.println("OK");
        } catch (Exception e) {
            System.err.println("Error converting file: " + e.getMessage());
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }
}
