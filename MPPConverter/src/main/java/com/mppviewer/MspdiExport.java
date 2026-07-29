package com.mppviewer;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import net.sf.mpxj.ConstraintType;
import net.sf.mpxj.Duration;
import net.sf.mpxj.ProjectFile;
import net.sf.mpxj.ProjectProperties;
import net.sf.mpxj.Relation;
import net.sf.mpxj.RelationType;
import net.sf.mpxj.Resource;
import net.sf.mpxj.ResourceAssignment;
import net.sf.mpxj.Task;
import net.sf.mpxj.TimeUnit;
import net.sf.mpxj.writer.FileFormat;
import net.sf.mpxj.writer.UniversalProjectWriter;

import java.io.File;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.HashMap;
import java.util.Map;

/**
 * Reads the app's native-plan interchange JSON and writes an MSPDI
 * (Microsoft Project XML) file that MS Project and other PM tools can open.
 */
public class MspdiExport {

    public static void run(String inputPath, String outputPath) throws Exception {
        JsonNode root = new ObjectMapper().readTree(new File(inputPath));

        ProjectFile project = new ProjectFile();
        ProjectProperties properties = project.getProjectProperties();
        properties.setProjectTitle(text(root, "title", "Project"));
        properties.setName(text(root, "title", "Project"));
        properties.setManager(text(root, "manager", ""));
        properties.setCompany(text(root, "company", ""));
        LocalDateTime statusDate = dateTime(root.path("statusDate"));
        if (statusDate != null) {
            properties.setStatusDate(statusDate);
        }

        Map<Integer, Resource> resourcesByID = new HashMap<>();
        for (JsonNode node : root.path("resources")) {
            Resource resource = project.addResource();
            int id = node.path("id").asInt();
            resource.setUniqueID(Integer.valueOf(id));
            resource.setName(text(node, "name", "Resource"));
            resource.setEmailAddress(text(node, "email", ""));
            resource.setGroup(text(node, "group", ""));
            resource.setInitials(text(node, "initials", ""));
            // MPXJ 13 models rates/max units via cost-rate and availability
            // tables; those are omitted from this first MSPDI export pass.
            resourcesByID.put(Integer.valueOf(id), resource);
        }

        Map<Integer, Task> tasksByID = new HashMap<>();
        Deque<Task> outlineStack = new ArrayDeque<>();
        Deque<Integer> levelStack = new ArrayDeque<>();

        for (JsonNode node : root.path("tasks")) {
            int outlineLevel = Math.max(1, node.path("outlineLevel").asInt(1));

            while (!levelStack.isEmpty() && levelStack.peek() >= outlineLevel) {
                levelStack.pop();
                outlineStack.pop();
            }

            Task task = outlineStack.isEmpty() ? project.addTask() : outlineStack.peek().addTask();
            int id = node.path("id").asInt();
            task.setUniqueID(Integer.valueOf(id));
            task.setName(text(node, "name", "Task"));
            task.setStart(dateTime(node.path("start")));
            task.setFinish(dateTime(node.path("finish")));
            task.setDuration(Duration.getInstance(node.path("durationDays").asInt(1), TimeUnit.DAYS));
            task.setMilestone(node.path("milestone").asBoolean(false));
            task.setPercentageComplete(Double.valueOf(node.path("percentComplete").asDouble(0)));
            String notes = text(node, "notes", "");
            if (!notes.isEmpty()) {
                task.setNotes(notes);
            }
            double cost = node.path("cost").asDouble(0);
            if (cost != 0) {
                task.setCost(Double.valueOf(cost));
            }
            task.setBaselineStart(dateTime(node.path("baselineStart")));
            task.setBaselineFinish(dateTime(node.path("baselineFinish")));
            task.setActualStart(dateTime(node.path("actualStart")));
            task.setActualFinish(dateTime(node.path("actualFinish")));

            String constraintType = text(node, "constraintType", "");
            LocalDateTime constraintDate = dateTime(node.path("constraintDate"));
            if (constraintDate != null && !constraintType.isEmpty()) {
                switch (constraintType) {
                    case "SNET" -> task.setConstraintType(ConstraintType.START_NO_EARLIER_THAN);
                    case "FNET" -> task.setConstraintType(ConstraintType.FINISH_NO_EARLIER_THAN);
                    case "MSO" -> task.setConstraintType(ConstraintType.MUST_START_ON);
                    case "MFO" -> task.setConstraintType(ConstraintType.MUST_FINISH_ON);
                    default -> task.setConstraintType(ConstraintType.AS_SOON_AS_POSSIBLE);
                }
                task.setConstraintDate(constraintDate);
            }

            tasksByID.put(Integer.valueOf(id), task);
            outlineStack.push(task);
            levelStack.push(outlineLevel);
        }

        // Predecessor links (second pass so forward references resolve).
        for (JsonNode node : root.path("tasks")) {
            Task task = tasksByID.get(Integer.valueOf(node.path("id").asInt()));
            if (task == null) {
                continue;
            }
            for (JsonNode predecessorID : node.path("predecessorIDs")) {
                Task predecessor = tasksByID.get(Integer.valueOf(predecessorID.asInt()));
                if (predecessor != null) {
                    task.addPredecessor(new Relation.Builder()
                        .targetTask(predecessor)
                        .type(RelationType.FINISH_START));
                }
            }
        }

        for (JsonNode node : root.path("assignments")) {
            Task task = tasksByID.get(Integer.valueOf(node.path("taskID").asInt()));
            JsonNode resourceIDNode = node.path("resourceID");
            if (task == null || resourceIDNode.isMissingNode() || resourceIDNode.isNull()) {
                continue;
            }
            Resource resource = resourcesByID.get(Integer.valueOf(resourceIDNode.asInt()));
            if (resource == null) {
                continue;
            }
            ResourceAssignment assignment = task.addResourceAssignment(resource);
            assignment.setUnits(Double.valueOf(node.path("units").asDouble(100)));
        }

        new UniversalProjectWriter(FileFormat.MSPDI).write(project, new File(outputPath));
    }

    private static String text(JsonNode node, String field, String fallback) {
        JsonNode value = node.path(field);
        return value.isTextual() ? value.asText() : fallback;
    }

    private static LocalDateTime dateTime(JsonNode node) {
        if (node == null || node.isMissingNode() || node.isNull() || !node.isTextual()) {
            return null;
        }
        String raw = node.asText();
        if (raw.isEmpty()) {
            return null;
        }
        try {
            return LocalDate.parse(raw).atTime(LocalTime.of(8, 0));
        } catch (Exception e) {
            return null;
        }
    }
}
