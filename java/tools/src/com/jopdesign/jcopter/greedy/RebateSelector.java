/*
 * This file is part of JOP, the Java Optimized Processor
 *   see <http://www.jopdesign.com/>
 *
 * Copyright (C) 2011, Stefan Hepp (stefan@stefant.org).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

package com.jopdesign.jcopter.greedy;

import com.jopdesign.common.MethodInfo;
import com.jopdesign.jcopter.analysis.AnalysisManager;
import com.jopdesign.jcopter.analysis.StacksizeAnalysis;
import org.apache.bcel.generic.InstructionHandle;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

/**
 * @author Stefan Hepp (stefan@stefant.org)
 */
public class RebateSelector implements CandidateSelector {

    protected static class RebateRatio implements Comparable<RebateRatio> {

         private final Candidate candidate;
         private final float ratio;

         private RebateRatio(Candidate candidate, float ratio) {
             this.candidate = candidate;
             this.ratio = ratio;
         }

         public Candidate getCandidate() {
             return candidate;
         }

         public float getRatio() {
             return ratio;
         }

         @Override
         public boolean equals(Object o) {
             if (this == o) return true;
             if (o == null || getClass() != o.getClass()) return false;

             RebateRatio that = (RebateRatio) o;

             return Float.compare(that.getRatio(), ratio) == 0 && candidate.equals(that.getCandidate());
         }

         @Override
         public int hashCode() {
             int result = candidate.hashCode();
             result = 31 * result + (ratio != +0.0f ? Float.floatToIntBits(ratio) : 0);
             return result;
         }

         @Override
         public int compareTo(RebateRatio o) {
             if (ratio == o.getRatio()) {
                 // since we want to keep different entries with the same ratio, use candidate as tiebreaker
                 if (candidate.equals(o.getCandidate())) return 0;
                 // TODO two candidates could still have the same hashCode .. we might want to use something else
                 return candidate.hashCode() < o.getCandidate().hashCode() ? -1 : 1;
             }
             return ratio < o.getRatio() ? -1 : 1;
         }
    }


    private class MethodData {
        private List<Candidate> candidates;
        private List<RebateRatio> ratios;

        private MethodData() {
            candidates = new ArrayList<Candidate>();
            ratios = new ArrayList<RebateRatio>();
        }

        public void addCandidates(Collection<Candidate> c) {
            candidates.addAll(c);
        }

        public List<Candidate> getCandidates() {
            return candidates;
        }

        public List<RebateRatio> getRatios() {
            return ratios;
        }
    }

    private final AnalysisManager analyses;
    private final Map<MethodInfo, MethodData> methodData;

    private TreeSet<RebateRatio> queue = new TreeSet<RebateRatio>();

    public RebateSelector(AnalysisManager analyses) {
        this.analyses = analyses;
        methodData = new HashMap<MethodInfo, MethodData>();
    }

    @Override
    public void initialize() {
    }

    public void addCandidates(MethodInfo method, Collection<Candidate> candidates) {
        MethodData data = methodData.get(method);
        if (data == null) {
            data = new MethodData();
            methodData.put(method, data);
        }
        data.addCandidates(candidates);
    }

    @Override
    public void removeCandidates(MethodInfo method) {
        MethodData data = methodData.remove(method);

        // TODO remove ratios from queue

    }

    @Override
    public void removeCandidates(MethodInfo method, InstructionHandle start, InstructionHandle end) {
        // TODO go through all candidates of the method, remove all with overlapping range (use positions to check)
        // for now, we just assume that candidates do not overlap ..

    }

    @Override
    public Collection<Candidate> getCandidates(MethodInfo method) {
        return methodData.get(method).getCandidates();
    }

    @Override
    public void updateCandidates(MethodInfo method, StacksizeAnalysis stacksizeAnalysis) {
        MethodData data = methodData.get(method);
        if (data == null) return;

        Iterator<Candidate> it = data.getCandidates().iterator();
        while (it.hasNext()) {
            Candidate c = it.next();
            if (!c.recalculate(analyses, stacksizeAnalysis)) {
                it.remove();
            }
        }
    }

    @Override
    public void updateSelection() {
        queue.clear();
        updateSelection(methodData.keySet());
    }

    @Override
    public void updateSelection(Set<MethodInfo> changedMethods) {



    }

    @Override
    public Collection<Candidate> selectNextCandidates() {


        return null;
    }


}
